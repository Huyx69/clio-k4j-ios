import SwiftUI

struct RouteView: View {
    @EnvironmentObject var obd: OBDManager
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                connectRow
                if showLog { logBox }
                statusMsg
                lcdHero
                tilesGrid
                if !mixNote.isEmpty { Text(mixNote).font(.footnote).foregroundColor(Theme.muted) }
                tripCard
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    @ViewBuilder private var connectRow: some View {
        if !obd.running {
            HStack(spacing: 10) {
                MainButton(title: "Connecter le boîtier", role: .primary) { obd.startScan() }
                MainButton(title: "Sans voiture", role: .secondary) { obd.startDemo() }
            }
        } else {
            MainButton(title: "Terminer le trajet", role: .secondary) { obd.stop() }
        }
    }

    private var logBox: some View {
        DisclosureGroup("Journal", isExpanded: $showLog) {
            ScrollView {
                Text(obd.ble.log.joined(separator: "\n"))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 220)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .foregroundColor(Theme.muted)
    }

    private var statusMsg: some View {
        Text(obd.statusMsg)
            .font(.footnote).foregroundColor(obd.connLevel == 3 ? Theme.bad : Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lcdHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instValue).font(.system(size: 90, weight: .bold)).monospacedDigit()
                        .foregroundColor(Theme.lcd).lineLimit(1).minimumScaleFactor(0.5)
                    Text(instUnit.uppercased()).font(.caption).bold().tracking(0.8)
                        .foregroundColor(Color(red: 0.769, green: 0.475, blue: 0.306))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    sideBig(fmt(moyValue, 1, "--.-"), "moy. trajet")
                    sideBig(fmt(obd.live.vit, 0, "0"), "km/h")
                }
            }
            rpmBar
        }
        .padding(14)
        .background(LinearGradient(colors: [Theme.lcdBg1, Theme.lcdBg2], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.227, green: 0.133, blue: 0.075)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sideBig(_ v: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(v).font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundColor(Theme.lcd)
            Text(label.uppercased()).font(.caption2).tracking(0.6)
                .foregroundColor(Color(red: 0.769, green: 0.475, blue: 0.306))
        }
    }

    private var rpmBar: some View {
        let rpm = obd.live.rpm ?? 0
        let pr = min(1, rpm / 6500)
        let red = rpm > K4J.redline
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.165, green: 0.102, blue: 0.063))
                RoundedRectangle(cornerRadius: 4)
                    .fill(red ? Theme.bad : Theme.lcd)
                    .frame(width: geo.size.width * pr)
            }
        }
        .frame(height: 8)
        .padding(.top, 6)
    }

    private var tilesGrid: some View {
        let d = obd.live
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            Tile(label: "Régime",      value: fmt(d.rpm, 0, "--"),  unit: "tr/min")
            Tile(label: "Eau",         value: fmt(d.eau, 0, "--"),  unit: "°C",
                 variant: eauVariant(d.eau))
            Tile(label: "Batterie",    value: fmt(d.bat, 1, "--"),  unit: "V",
                 variant: batVariant(d.bat))
            Tile(label: "Admission",   value: fmt(d.map, 0, "--"),  unit: "kPa")
            Tile(label: "Papillon",    value: fmt(d.pap, 0, "--"),  unit: "%")
            Tile(label: "Charge",      value: fmt(d.charge, 0, "--"),unit: "%")
            Tile(label: "Air admis",   value: fmt(d.air, 0, "--"),  unit: "°C")
            Tile(label: "Avance",      value: fmt(d.av,  1, "--"),  unit: "°")
            Tile(label: "Sonde O2",    value: fmt(d.o2,  2, "--"),  unit: "V")
            Tile(label: "Corr. courte",value: fmt(d.stft,1, "--"),  unit: "%")
            Tile(label: "Corr. longue",value: fmt(d.ltft,1, "--"),  unit: "%",
                 variant: ltftVariant(d.ltft, d.eau))
            Tile(label: "Débit",       value: fmt(d.lh,  2, "--"),  unit: "L/h")
        }
    }

    private var tripCard: some View {
        let s = obd.tripSeconds
        let dur = "\(s / 60):\(String(format: "%02d", s % 60))"
        return VStack(spacing: 10) {
            HStack {
                stat("km",         String(format: "%.1f", obd.tripKm))
                stat("litres",     String(format: "%.2f", obd.tripLitres))
                stat("durée",      dur)
                stat("tr/min max", String(obd.tripMaxRpm))
            }
            Text("Compteurs du trajet en cours. Détails complets dans Trajets.")
                .font(.caption).foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(label.uppercased()).font(.caption2).tracking(0.6).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Valeurs

    private var instValue: String {
        let v = obd.live.vit ?? 0
        if v > 5 {
            let l100 = obd.live.lh / v * 100
            return String(format: "%.1f", min(l100, 99.9))
        }
        return String(format: "%.2f", obd.live.lh)
    }
    private var instUnit: String { (obd.live.vit ?? 0) > 5 ? "L/100 km instantané" : "L/h à l'arrêt" }
    private var moyValue: Double? {
        obd.tripKm > 0.3 ? obd.tripLitres / obd.tripKm * 100 : nil
    }

    private func fmt(_ v: Double?, _ d: Int, _ def: String) -> String {
        guard let v = v else { return def }
        return String(format: "%.\(d)f", v)
    }

    private func eauVariant(_ v: Double?) -> Tile.Variant {
        guard let v = v else { return .normal }
        if v > 105 { return .bad }
        if v > 98 { return .warn }
        return .normal
    }
    private func batVariant(_ v: Double?) -> Tile.Variant {
        guard let v = v else { return .normal }
        return (v < 12.2 || v > 14.8) ? .warn : .normal
    }
    private func ltftVariant(_ lt: Double?, _ eau: Double?) -> Tile.Variant {
        guard let lt = lt, let e = eau, e >= 75 else { return .normal }
        if abs(lt) > 15 { return .bad }
        if abs(lt) > 8 { return .warn }
        return .normal
    }

    private var mixNote: String {
        guard let lt = obd.live.ltft else { return "" }
        let eth = obd.state.carbu == "E85" || obd.state.carbu == "MIX"
        let eau = obd.live.eau ?? 0
        if eau < 75 { return "Richesse : attends que l'eau dépasse 75 °C pour juger." }
        if lt > 8 {
            return String(format: "Mélange trop pauvre : le calculateur ajoute %.0f %% de carburant.", lt)
                + (eth ? " Le kit éthanol n'en injecte pas assez : monte un peu son réglage." :
                        " Cherche une prise d'air ou un injecteur encrassé.")
        }
        if lt < -8 {
            return String(format: "Mélange trop riche : le calculateur retire %.0f %% de carburant.", -lt)
                + (eth ? " Le kit éthanol en injecte trop : baisse un peu son réglage." : "")
        }
        return String(format: "Richesse bien réglée (correction longue %+.1f %%).", lt)
    }
}
