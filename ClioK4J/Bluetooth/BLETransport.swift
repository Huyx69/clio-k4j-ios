import Foundation
import CoreBluetooth
import Combine

/// Transport ELM327 via Bluetooth LE (dongle OBDBLE). Expose un flux de texte
/// reçu et une méthode d'écriture par trames de 20 octets.
final class BLETransport: NSObject {
    enum State: Equatable { case idle, scanning, connecting, ready, failed(String), disconnected }

    // UUIDs couramment utilisés par les dongles ELM327 BLE
    static let serviceUUIDs: [CBUUID] = [
        CBUUID(string: "FFF0"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "18F0"),
        CBUUID(string: "FFE5"),
        CBUUID(string: "AE30"),
        CBUUID(string: "FEE7"),
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"),
    ]

    @Published private(set) var state: State = .idle
    @Published private(set) var deviceName: String = ""
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published private(set) var log: [String] = []

    /// Texte reçu depuis le dongle (chunks UTF-8).
    let textSubject = PassthroughSubject<String, Never>()
    /// Événement de déconnexion inattendue.
    let disconnectSubject = PassthroughSubject<Void, Never>()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var scanTimer: Timer?

    override init() {
        super.init()
        // Identifiant de restauration: iOS peut relancer l'app en arrière-plan
        // quand le dongle envoie une notification BLE, même après kill du système.
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "cliok4j.central.v1",
                CBCentralManagerOptionShowPowerAlertKey: true,
            ]
        )
    }

    /// Appelé par iOS quand le système relance l'app pour un événement BLE.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        logLine("Restauration BLE par iOS…")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let first = peripherals.first {
            self.peripheral = first
            first.delegate = self
            logLine("Périphérique restauré: \(first.name ?? "sans nom")")
            if first.state == .connected {
                deviceName = first.name ?? "OBDBLE"
                state = .connecting
                first.discoverServices(nil)
            }
        }
    }

    func logLine(_ s: String) {
        let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("\(t)  \(s)")
        if log.count > 120 { log.removeFirst(log.count - 120) }
    }

    func startScan() {
        guard central.state == .poweredOn else {
            logLine("Bluetooth pas prêt (\(central.state.rawValue))")
            state = .failed("Bluetooth non disponible. Active-le dans Réglages.")
            return
        }
        discovered.removeAll()
        state = .scanning
        logLine("Recherche de boîtiers ELM327…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if case .scanning = self.state { self.central.stopScan(); self.logLine("Fin du scan.") }
        }
    }

    func stopScan() {
        central.stopScan()
        scanTimer?.invalidate()
    }

    func connect(_ p: CBPeripheral) {
        stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        logLine("Connexion à \(p.name ?? "sans nom")…")
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        state = .disconnected
    }

    func write(_ text: String) {
        guard let p = peripheral, let w = writeChar, let data = text.data(using: .utf8) else { return }
        let chunkSize = 20
        var i = 0
        while i < data.count {
            let end = min(i + chunkSize, data.count)
            let chunk = data.subdata(in: i..<end)
            let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(chunk, for: w, type: type)
            i = end
        }
    }
}

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logLine("Bluetooth: \(central.state.rawValue)")
        if central.state != .poweredOn {
            state = .failed("Active le Bluetooth.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // On garde tout, l'utilisateur choisit (souvent "OBDBLE", "V-LINK", "VEEPEAK", "VGate").
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logLine("Connecté. Recherche des services…")
        deviceName = peripheral.name ?? "OBDBLE"
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logLine("Échec: \(error?.localizedDescription ?? "?")")
        state = .failed(error?.localizedDescription ?? "Connexion refusée.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logLine("Déconnecté: \(error?.localizedDescription ?? "normal")")
        state = .disconnected
        disconnectSubject.send()
    }
}

extension BLETransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for svc in peripheral.services ?? [] {
            logLine("Service \(svc.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            let p = c.properties
            let flags = (p.contains(.notify) ? "N" : "") + (p.contains(.indicate) ? "I" : "") +
                       (p.contains(.write) ? "W" : "") + (p.contains(.writeWithoutResponse) ? "w" : "")
            logLine("  \(service.uuid.uuidString.suffix(4))/\(c.uuid.uuidString.suffix(4)) \(flags)")
            if notifyChar == nil, p.contains(.notify) || p.contains(.indicate) {
                notifyChar = c
                peripheral.setNotifyValue(true, for: c)
            }
            if writeChar == nil, p.contains(.write) || p.contains(.writeWithoutResponse) {
                writeChar = c
            }
        }
        if notifyChar != nil && writeChar != nil {
            state = .ready
            logLine("Prêt pour ELM327.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let s = String(data: data, encoding: .utf8) else { return }
        textSubject.send(s)
    }
}
