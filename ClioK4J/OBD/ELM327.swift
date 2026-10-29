import Foundation
import Combine

/// Petite file d'attente async pour sérialiser les commandes ELM327.
actor AsyncLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if let w = waiters.first { waiters.removeFirst(); w.resume() }
        else { busy = false }
    }
}

/// Protocole ELM327: envoie des commandes AT et des PIDs OBD-II, attend le prompt ">".
/// Les commandes sont sérialisées pour qu'une lecture DTC et la boucle live ne se marchent pas dessus.
final class ELM327 {
    private let transport: BLETransport
    private var buffer = ""
    private var pending: ((String) -> Void)?
    private var cancellable: AnyCancellable?
    private let lock = AsyncLock()

    private(set) var supported: [UInt8]? = nil

    init(_ transport: BLETransport) {
        self.transport = transport
        cancellable = transport.textSubject.receive(on: DispatchQueue.main)
            .sink { [weak self] s in self?.onText(s) }
    }

    private func onText(_ s: String) {
        buffer += s
        if buffer.contains(">") {
            let r = buffer
            buffer = ""
            let cb = pending
            pending = nil
            cb?(r)
        }
    }

    /// Envoie une commande et attend la réponse jusqu'au prompt. Timeout par défaut 2.5s.
    func cmd(_ c: String, timeout: TimeInterval = 2.5) async -> String {
        await lock.acquire()
        let result: String = await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                self.buffer = ""
                self.pending = { cont.resume(returning: $0) }
                self.transport.write(c + "\r")
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self = self, self.pending != nil else { return }
                    self.pending = nil
                    cont.resume(returning: "TIMEOUT")
                }
            }
        }
        await lock.release()
        return result
    }

    private func lines(_ r: String, _ c: String) -> [String] {
        r.replacingOccurrences(of: ">", with: "")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.replacingOccurrences(of: " ", with: "").uppercased() }
            .filter {
                !$0.isEmpty && $0 != c && !$0.hasPrefix("SEARCHING") &&
                !$0.hasPrefix("BUSINIT") && $0 != "OK"
            }
    }

    private func bytes(_ hex: String) -> [UInt8]? {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            guard let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) else { return nil }
            guard let n = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(n)
            i = j
        }
        return out
    }

    /// Interroge un PID (mode 01) et renvoie les octets de données.
    func pid(_ p: String, timeout: TimeInterval = 2.5) async -> [UInt8]? {
        let r = await cmd("01" + p, timeout: timeout)
        for l in lines(r, "01" + p) {
            if let range = l.range(of: "41" + p) {
                let after = String(l[range.upperBound...])
                return bytes(after)
            }
        }
        return nil
    }

    /// Lit les codes défaut en mode 03 ou 07.
    func readDTC(mode: String, timeout: TimeInterval = 6) async -> [String] {
        let r = await cmd(mode, timeout: timeout)
        var out: [String] = []
        let modeAnswer = String(40 + (Int(mode) ?? 0))
        for l in lines(r, mode) {
            guard let range = l.range(of: modeAnswer) else { continue }
            let after = String(l[range.upperBound...])
            var k = after.startIndex
            while let j = after.index(k, offsetBy: 4, limitedBy: after.endIndex) {
                let code = String(after[k..<j])
                if code != "0000" { out.append(Self.decodeDTC(code)) }
                k = j
            }
        }
        return Array(NSOrderedSet(array: out)) as? [String] ?? out
    }

    func clearDTC() async -> Bool {
        let r = await cmd("04", timeout: 6)
        return lines(r, "04").contains(where: { $0.contains("44") })
    }

    func readVoltage() async -> Double? {
        let r = await cmd("ATRV")
        let regex = try? NSRegularExpression(pattern: #"(\d+\.\d)\s*V"#, options: .caseInsensitive)
        if let m = regex?.firstMatch(in: r, options: [], range: NSRange(r.startIndex..., in: r)),
           let range = Range(m.range(at: 1), in: r) {
            return Double(r[range])
        }
        return nil
    }

    /// Init ELM327 + sélection de protocole adapté Clio 2 K-line (KWP2000/ISO9141).
    func initialize() async -> Bool {
        _ = await cmd("ATZ", timeout: 4)
        for c in ["ATE0","ATL0","ATS0","ATH0","ATAT1"] { _ = await cmd(c) }
        for sp in ["ATSP0","ATSP5","ATSP4","ATSP3"] {
            _ = await cmd(sp)
            let r = await cmd("0100", timeout: 20)
            if let l = lines(r, "0100").first(where: { $0.contains("4100") }),
               let range = l.range(of: "4100") {
                let after = String(l[range.upperBound...])
                if let b = bytes(after), b.count >= 4 {
                    supported = b
                    return true
                }
            }
        }
        return false
    }

    func isSupported(_ pid: String) -> Bool {
        guard let s = supported else { return true }
        guard let n = Int(pid, radix: 16).map({ $0 - 1 }), n < 32 else { return true }
        return ((s[n >> 3] >> (7 - (n & 7))) & 1) == 1
    }

    // MARK: - DTC decode

    static func decodeDTC(_ h: String) -> String {
        guard h.count >= 4, let a = UInt8(h.prefix(2), radix: 16) else { return h }
        let prefix = ["P","C","B","U"][Int(a >> 6)]
        let digit1 = String((a >> 4) & 3)
        let digit2 = String((a & 15), radix: 16).uppercased()
        return prefix + digit1 + digit2 + h.suffix(2)
    }

    static func describe(_ code: String) -> String {
        guard code.count >= 5, code.first == "P", code[code.index(after: code.startIndex)] == "0" else {
            return "Code constructeur Renault (consulte DDT4all)"
        }
        let numStr = String(code.suffix(3))
        if code.hasPrefix("P030"), let last = code.last, "1234".contains(last) {
            return "Ratés d'allumage cylindre \(last) (bougie, bobine, injecteur)"
        }
        guard let n = Int(numStr, radix: 16) else { return "Voir la description en ligne" }
        for (a, b, label) in dtcTable where n >= a && n <= b { return label }
        return "Voir la description du code en ligne"
    }

    private static let dtcTable: [(Int, Int, String)] = [
        (0x100, 0x104, "Débitmètre d'air"),
        (0x105, 0x109, "Capteur de pression d'admission"),
        (0x110, 0x114, "Sonde de température d'air"),
        (0x115, 0x119, "Sonde de température d'eau"),
        (0x120, 0x124, "Potentiomètre de papillon"),
        (0x125, 0x125, "Moteur trop lent à chauffer (thermostat ?)"),
        (0x130, 0x135, "Sonde lambda amont"),
        (0x136, 0x141, "Sonde lambda aval"),
        (0x170, 0x172, "Richesse mal régulée (prise d'air, injecteur, pression)"),
        (0x201, 0x204, "Injecteur"),
        (0x230, 0x230, "Relais de pompe à essence"),
        (0x300, 0x300, "Ratés d'allumage sur plusieurs cylindres"),
        (0x301, 0x304, "Ratés d'allumage sur un cylindre"),
        (0x325, 0x334, "Capteur de cliquetis"),
        (0x335, 0x339, "Capteur de régime / PMH"),
        (0x340, 0x344, "Capteur d'arbre à cames"),
        (0x351, 0x354, "Bobine d'allumage"),
        (0x420, 0x420, "Catalyseur peu efficace"),
        (0x440, 0x446, "Circuit canister (vapeurs d'essence)"),
        (0x500, 0x503, "Capteur de vitesse"),
        (0x505, 0x509, "Régulation de ralenti"),
        (0x560, 0x563, "Tension batterie / charge"),
        (0x600, 0x606, "Calculateur moteur"),
    ]
}
