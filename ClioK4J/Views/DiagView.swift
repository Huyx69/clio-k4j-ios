import SwiftUI

struct DiagView: View {
    @EnvironmentObject var obd: OBDManager
    @State private var mil: Bool? = nil
    @State private var count: Int? = nil
    @State private var codes: [DTC] = []
    @State private var msg: String = ""
    @State private var armed = false
    @State private var reading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(text: "Codes défaut moteur")
                card
                HStack(spacing: 10) {
                    MainButton(title: reading ? "Lecture…" : "Lire les codes",
                               role: .primary, disabled: reading || !obd.running) {
                        Task { await read() }
                    }
                    MainButton(title: armed ? "Confirmer effacement" : "Effacer les codes",
                               role: armed ? .dangerArmed : .danger,
                               disabled: !obd.running) {
                        Task { await clear() }
                    }
                }
                Text(msg.isEmpty ?
                     "Effacer éteint le voyant mais ne répare rien : si la panne est là, le code revient. Pour effacer : moteur coupé, contact mis."
                     : msg)
                    .font(.footnote).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                milIcon
                Text(milText).bold()
            }
            if codes.isEmpty && (mil != nil || count != nil) {
                Text("Aucun code défaut moteur.").foregroundColor(Theme.fg)
            }
            ForEach(codes) { c in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(c.code).font(.system(size: 20, weight: .bold)).foregroundColor(c.pending ? Theme.muted : Theme.warn)
                    Text(c.desc + (c.pending ? "  (en attente)" : "")).font(.footnote).foregroundColor(Theme.fg)
                    Spacer()
                }
            }
            if obd.isDemo { Text("Codes simulés (mode démo)").font(.caption).foregroundColor(Theme.warn) }
            if !obd.running { Text("Connecte le boîtier depuis Route.").foregroundColor(Theme.muted) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var milIcon: some View {
        Image(systemName: "engine.combustion")
            .foregroundColor(mil == true ? Theme.warn : Theme.line)
            .font(.title2)
    }
    private var milText: String {
        if mil == nil { return "Voyant moteur inconnu" }
        let base = mil == true ? "Voyant moteur allumé" : "Voyant moteur éteint"
        if let c = count, c > 0 { return "\(base) · \(c) code(s)" }
        return base
    }

    private func read() async {
        reading = true
        let r = await obd.readDTCs()
        mil = r.mil; count = r.count; codes = r.codes
        reading = false
    }

    private func clear() async {
        guard obd.running else { return }
        if !armed {
            armed = true
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { armed = false }
            }
            return
        }
        armed = false
        let ok = await obd.clearDTCs()
        msg = ok ? "Codes effacés. Le calculateur réapprend ses corrections sur les prochains km." :
                   "La voiture a refusé. Coupe le moteur, laisse le contact et réessaie."
        await read()
    }
}
