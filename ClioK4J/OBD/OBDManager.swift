import Foundation
import Combine
import CoreBluetooth
import UIKit

/// Chef d'orchestre: BLE + ELM327 + boucle de lecture + trajet + persistance.
/// Observable depuis SwiftUI et aussi utilisé par la scène CarPlay.
@MainActor
final class OBDManager: ObservableObject {
    static let shared = OBDManager()

    @Published var state: AppState = Storage.shared.load()
    @Published var live: LiveData = LiveData()
    @Published var connStatus: String = "Déconnecté"
    @Published var connLevel: Int = 0 // 0 off, 1 busy, 2 ok, 3 err
    @Published var statusMsg: String = "Contact mis, boîtier branché, puis Connecter."
    @Published var isDemo: Bool = false
    @Published var running: Bool = false
    @Published var discovered: [CBPeripheral] = []
    @Published var pickerVisible: Bool = false
    @Published var tripKm: Double = 0
    @Published var tripLitres: Double = 0
    @Published var tripSeconds: Int = 0
    @Published var tripMaxRpm: Int = 0

    let ble = BLETransport()
    private lazy var elm: ELM327 = ELM327(ble)

    private var loopTask: Task<Void, Never>?
    private var trip: Trip?
    private var papMin: Double = 100
    private var cancellables = Set<AnyCancellable>()
    private var demoStart: Date?
    private var reconnecting = false

    /// Observe les scans et l'état BLE pour mettre à jour l'UI.
    init() {
        ble.$discovered.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.discovered = $0 }
            .store(in: &cancellables)
        ble.disconnectSubject.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleDisconnect() }
            .store(in: &cancellables)
        ble.$state.receive(on: DispatchQueue.main)
            .sink { [weak self] st in
                guard let self = self else { return }
                switch st {
                case .scanning:
                    self.connStatus = "Recherche…"; self.connLevel = 1
                case .connecting:
                    self.connStatus = "Connexion…"; self.connLevel = 1
                case .ready:
                    self.connStatus = "Liaison OK"; self.connLevel = 1
                case .failed(let m):
                    self.connStatus = "Erreur"; self.connLevel = 3; self.statusMsg = m
                case .disconnected:
                    if !self.reconnecting && !self.isDemo { self.connStatus = "Déconnecté"; self.connLevel = 0 }
                default: break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Carburant / état

    func setFuel(_ id: String) { state.carbu = id; save() }

    func save() { Storage.shared.save(state) }

    // MARK: - Connexion

    /// Lance le scan et laisse l'utilisateur choisir le périphérique.
    func startScan() {
        pickerVisible = true
        isDemo = false
        ble.startScan()
    }

    func connect(_ p: CBPeripheral) {
        pickerVisible = false
        ble.connect(p)
        // Attend l'état .ready puis init ELM.
        Task { [weak self] in
            guard let self = self else { return }
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if case .ready = self.ble.state { break }
                if case .failed = self.ble.state { return }
            }
            await self.beginSession()
        }
    }

    func startDemo() {
        isDemo = true
        demoStart = Date()
        connStatus = "Démo"; connLevel = 2
        statusMsg = "Mode démo: rien de tout ça ne vient de ta voiture."
        startTrip()
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        SilentAudio.shared.start()
        loopTask?.cancel()
        loopTask = Task { [weak self] in await self?.demoLoop() }
    }

    func stop() {
        running = false
        reconnecting = false
        loopTask?.cancel()
        loopTask = nil
        endTrip()
        if !isDemo { ble.disconnect() }
        UIApplication.shared.isIdleTimerDisabled = false
        SilentAudio.shared.stop()
        NowPlayingBridge.shared.clear()
        connStatus = "Déconnecté"; connLevel = 0
        statusMsg = "Trajet enregistré. Il est dans l'onglet Trajets."
    }

    // MARK: - Session réelle

    private func beginSession() async {
        connStatus = "Calculateur…"; connLevel = 1
        let ok = await elm.initialize()
        if !ok {
            connStatus = "Pas de calculateur"; connLevel = 3
            statusMsg = "Le boîtier répond mais pas la voiture. Mets le contact, attends 5s, réessaie."
            ble.disconnect()
            return
        }
        connStatus = "Connecté"; connLevel = 2
        statusMsg = "Connecté à \(ble.deviceName). Lance Lecture en cours sur CarPlay pour voir le dashboard."
        startTrip()
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        SilentAudio.shared.start()
        loopTask?.cancel()
        loopTask = Task { [weak self] in await self?.realLoop() }
    }

    private func realLoop() async {
        var n = 0
        var prev = Date()
        var bat: Double? = nil
        let fastKeys: [(String, String, (UInt8, UInt8) -> Double)] = [
            ("rpm",  "0C", { Double(UInt16($0) * 256 + UInt16($1)) / 4 }),
            ("vit",  "0D", { Double($0) * 1 + Double($1) * 0 }),
            ("map",  "0B", { Double($0) * 1 + Double($1) * 0 }),
            ("pap",  "11", { Double($0) * 100 / 255 + Double($1) * 0 }),
            ("stft", "06", { (Double($0) - 128) * 100 / 128 + Double($1) * 0 }),
        ]
        let slowKeys: [(String, String, (UInt8, UInt8) -> Double)] = [
            ("eau",    "05", { Double($0) - 40 + Double($1) * 0 }),
            ("air",    "0F", { Double($0) - 40 + Double($1) * 0 }),
            ("ltft",   "07", { (Double($0) - 128) * 100 / 128 + Double($1) * 0 }),
            ("charge", "04", { Double($0) * 100 / 255 + Double($1) * 0 }),
            ("av",     "0E", { Double($0) / 2 - 64 + Double($1) * 0 }),
            ("o2",     "14", { Double($0) / 200 + Double($1) * 0 }),
        ]
        while running && !Task.isCancelled {
            for (k, p, f) in fastKeys where elm.isSupported(p) {
                guard let b = await elm.pid(p), !b.isEmpty else { setLive(k, nil); continue }
                let v = f(b[0], b.count > 1 ? b[1] : 0)
                setLive(k, v)
            }
            if n % 5 == 0 {
                for (k, p, f) in slowKeys where elm.isSupported(p) {
                    guard let b = await elm.pid(p), !b.isEmpty else { setLive(k, nil); continue }
                    let v = f(b[0], b.count > 1 ? b[1] : 0)
                    setLive(k, v)
                }
                bat = await elm.readVoltage()
                live.bat = bat
            }
            n += 1
            let now = Date()
            let dt = now.timeIntervalSince(prev)
            prev = now
            live.lh = debit(live)
            tick(dt)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func setLive(_ k: String, _ v: Double?) {
        switch k {
        case "rpm": live.rpm = v
        case "vit": live.vit = v
        case "map": live.map = v
        case "pap": live.pap = v
        case "stft": live.stft = v
        case "ltft": live.ltft = v
        case "eau": live.eau = v
        case "air": live.air = v
        case "charge": live.charge = v
        case "av": live.av = v
        case "o2": live.o2 = v
        default: break
        }
    }

    // MARK: - Démo

    private func demoLoop() async {
        var prev = Date()
        while running && !Task.isCancelled {
            let t = Date().timeIntervalSince(demoStart ?? Date())
            live = simulate(t)
            live.lh = debit(live)
            let dt = Date().timeIntervalSince(prev); prev = Date()
            tick(dt)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func simulate(_ t: TimeInterval) -> LiveData {
        var d = LiveData()
        let v = max(0, 55 + 45 * sin(t/25) + 8 * sin(t/4))
        let g: Int = v < 18 ? 1 : v < 35 ? 2 : v < 55 ? 3 : v < 80 ? 4 : 5
        let ratio: [Double] = [0,120,70,48,37,30]
        d.vit = v
        d.rpm = max(820, v * ratio[g] + sin(t*3) * 40)
        let acc = cos(t/25) * 45/25 + cos(t/4) * 8/4
        let pap = acc < -0.3 ? 0 : min(60, 8 + acc*20 + v/8)
        d.pap = pap + 11.8
        d.map = (pap == 0 && (d.rpm ?? 0) > 1300) ? 22 : min(98, 30 + pap * 1.1)
        d.eau = min(89, 25 + t/3)
        d.air = 24
        d.charge = d.map! * 0.9
        d.av = 18 + sin(t)
        d.o2 = 0.45 + 0.4 * sin(t*5)
        d.stft = 3 * sin(t*2)
        d.ltft = 2.3
        d.bat = 13.8 + 0.2 * sin(t)
        return d
    }

    // MARK: - Conso

    private func debit(_ d: LiveData) -> Double {
        guard let rpm = d.rpm, let map = d.map, rpm >= 300 else { return 0 }
        if let p = d.pap { papMin = min(papMin, p) }
        let papRel: Double? = d.pap.map { $0 - papMin }
        if let pr = papRel, pr < 1.5, rpm > 1300, (d.vit ?? 0) > 15, map < 35 {
            return 0 // Coupure d'injection
        }
        let tk = (d.air ?? 20) + 273.15
        let airGs = map * 1000 * (K4J.cyl / 1000) * (rpm / 120) * K4J.ve / (K4J.R * tk) * 1000
        let full = (papRel ?? 0) >= 70
        let f = Fuels.by(state.carbu)
        let carbGs = airGs / (f.afr * (full ? K4J.lambdaFull : 1))
        return carbGs * 3600 / f.density * state.facteur
    }

    // MARK: - Trajet

    private struct Trip {
        var debut: Date
        var km: Double = 0
        var litres: Double = 0
        var maxRpm: Double = 0
        var maxEau: Double = 0
        var demo: Bool
        var pts: [TripPoint] = []
        var lastPt: Date = .distantPast
        var trou: Double = 0
    }

    private func startTrip() {
        trip = Trip(debut: Date(), demo: isDemo)
        papMin = 100
        tripKm = 0; tripLitres = 0; tripSeconds = 0; tripMaxRpm = 0
    }

    private func tick(_ dt: TimeInterval) {
        guard var t = trip else { return }
        if dt > 5 { t.trou += dt; trip = t; return }
        let v = live.vit ?? 0
        t.km += v * dt / 3600
        t.litres += live.lh * dt / 3600
        t.maxRpm = max(t.maxRpm, live.rpm ?? 0)
        t.maxEau = max(t.maxEau, live.eau ?? 0)
        let now = Date()
        if now.timeIntervalSince(t.lastPt) >= 1 {
            t.lastPt = now
            t.pts.append(TripPoint(
                s: Int(now.timeIntervalSince(t.debut)),
                rpm: r1(live.rpm), vit: r1(v), map: r1(live.map), pap: r1(live.pap),
                eau: r1(live.eau), stft: r1(live.stft), ltft: r1(live.ltft),
                bat: r1(live.bat), lh: Double(Int(live.lh * 100)) / 100
            ))
            if t.pts.count > 14400 { t.pts.removeFirst() }
        }
        trip = t
        tripKm = t.km
        tripLitres = t.litres
        tripSeconds = Int(Date().timeIntervalSince(t.debut))
        tripMaxRpm = Int(t.maxRpm.rounded())

        // Pousse les infos vers CarPlay via Now Playing.
        NowPlayingBridge.shared.update(
            live: live,
            trip: (km: t.km, litres: t.litres, seconds: tripSeconds),
            fuelName: Fuels.by(state.carbu).name
        )
    }

    private func r1(_ v: Double?) -> Double? {
        guard let v = v else { return nil }
        return (v * 10).rounded() / 10
    }

    private func endTrip() {
        guard let t = trip else { return }
        trip = nil
        if t.km < 0.05 && t.pts.count < 10 { return }
        let rec = TripRecord(
            debut: t.debut.timeIntervalSince1970,
            fin: Date().timeIntervalSince1970,
            km: Double(Int(t.km * 100)) / 100,
            litres: Double(Int(t.litres * 1000)) / 1000,
            maxRpm: Int(t.maxRpm.rounded()),
            maxEau: Int(t.maxEau.rounded()),
            demo: t.demo,
            pts: t.pts,
            trou: Int(t.trou.rounded()),
            carbu: state.carbu
        )
        state.trajets.insert(rec, at: 0)
        while state.trajets.count > 15 { state.trajets.removeLast() }
        if !t.demo {
            state.km += t.km
            state.litresCalc += t.litres
            if t.trou > 120 { state.incomplet = true }
        }
        save()
    }

    // MARK: - Déconnexion / reconnexion

    private func handleDisconnect() {
        guard running && !reconnecting else { return }
        running = false
        if isDemo { return }
        reconnecting = true
        connStatus = "Reconnexion…"; connLevel = 1
        statusMsg = "Liaison perdue, tentative de reconnexion…"
        Task { await self.reconnectLoop() }
    }

    private func reconnectLoop() async {
        let start = Date()
        while reconnecting {
            if UIApplication.shared.applicationState == .active {
                // Rejoint le dernier périphérique si retrouvé en scan.
                ble.startScan()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let p = ble.discovered.first(where: { $0.name == ble.deviceName }) {
                    ble.connect(p)
                    for _ in 0..<30 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if case .ready = ble.state { break }
                    }
                    if await elm.initialize() {
                        reconnecting = false
                        running = true
                        connStatus = "Connecté"; connLevel = 2
                        statusMsg = "Reconnecté. Le trajet continue."
                        loopTask?.cancel()
                        loopTask = Task { [weak self] in await self?.realLoop() }
                        return
                    }
                }
            }
            if Date().timeIntervalSince(start) > 15 * 60 {
                reconnecting = false
                endTrip()
                connStatus = "Coupé"; connLevel = 3
                statusMsg = "Pas de reconnexion depuis 15 min: trajet enregistré."
                return
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: - DTC

    func readDTCs() async -> (mil: Bool?, count: Int?, codes: [DTC]) {
        guard running else { return (nil, nil, []) }
        var mil: Bool? = nil
        var count: Int? = nil
        if let b = await elm.pid("01", timeout: 4), !b.isEmpty {
            mil = (b[0] & 0x80) != 0
            count = Int(b[0] & 0x7F)
        }
        let conf = await elm.readDTC(mode: "03")
        let pend = (await elm.readDTC(mode: "07")).filter { !conf.contains($0) }
        var all: [DTC] = []
        for c in conf { all.append(DTC(code: c, desc: ELM327.describe(c), pending: false)) }
        for c in pend { all.append(DTC(code: c, desc: ELM327.describe(c), pending: true)) }
        return (mil, count, all)
    }

    func clearDTCs() async -> Bool {
        guard running else { return false }
        return await elm.clearDTC()
    }

    // MARK: - Pleins

    func savePlein(litres: Double, prix: Double?) -> String {
        let date = ISO8601DateFormatter().string(from: Date())
        if state.km < 1 {
            state.pleins.insert(Plein(date: date, litres: litres, km: nil, reel: nil, calc: nil,
                                       calibre: false, depart: true, carbu: state.carbu, prix: prix), at: 0)
            state.incomplet = false
            save()
            return "Point de départ enregistré. Enregistre tous tes trajets jusqu'au prochain plein à ras."
        }
        let reel = litres / state.km * 100
        let calc = state.litresCalc / state.km * 100
        let ratio = state.litresCalc > 0 ? litres / state.litresCalc : 1
        var note = ""
        let calibre = state.km >= 80 && ratio > 0.6 && ratio < 1.6 && !state.incomplet
        if state.km < 80 {
            note = "Moins de 80 km: trop court pour calibrer, conso notée."
        } else if state.incomplet {
            note = "Un trajet a eu des coupures: calibration ignorée pour ce plein."
        } else if !calibre {
            note = String(format: "Écart trop grand (×%.2f): un trajet n'a sûrement pas été enregistré. Calibration ignorée.", ratio)
        } else {
            let n = state.pleins.filter { $0.calibre }.count
            let w = n == 0 ? 1.0 : 0.5
            let old = state.facteur
            state.facteur = ((old * (1 - w + w * ratio)) * 10000).rounded() / 10000
            note = String(format: "Calibration: %.3f → %.3f.", old, state.facteur)
        }
        state.pleins.insert(Plein(
            date: date, litres: litres,
            km: (state.km * 10).rounded() / 10,
            reel: (reel * 100).rounded() / 100,
            calc: (calc * 100).rounded() / 100,
            calibre: calibre, depart: false, carbu: state.carbu, prix: prix
        ), at: 0)
        state.km = 0
        state.litresCalc = 0
        state.incomplet = false
        save()
        let base = String(format: "%.1f L/100 réels sur ce plein (calculé: %.1f)", reel, calc)
        let euro = prix.map { String(format: ", soit %.2f €/100 km", reel * $0) } ?? ""
        return "\(base)\(euro). \(note)"
    }
}
