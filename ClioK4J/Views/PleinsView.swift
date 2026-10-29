import SwiftUI

struct PleinsView: View {
    @EnvironmentObject var obd: OBDManager
    @State private var litres: String = ""
    @State private var prix: String = ""
    @State private var msg: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(text: "Plein & calibration")
                fuelCard
                calibCard
                pleinsList
                Text("La conso est calculée à partir de la pression d'admission (ton moteur n'a pas de débitmètre). À chaque plein, l'app compare son calcul à la pompe et se corrige.")
                    .font(.caption).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
    }

    private var fuelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Carburant dans le réservoir").font(.footnote).foregroundColor(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                fuelBtn("E85",  "E85")
                fuelBtn("MIX",  "Mélange E85+SP")
                fuelBtn("SP95", "SP95-E10")
                fuelBtn("SP98", "SP98")
            }
            Text("Litres affichés sur la pompe (plein à ras)").font(.footnote).foregroundColor(Theme.muted)
            TextField("38,50", text: $litres)
                .keyboardType(.decimalPad)
                .textFieldStyle(LCDFieldStyle())
            Text("Prix au litre en € (facultatif)").font(.footnote).foregroundColor(Theme.muted)
            TextField("1,79", text: $prix)
                .keyboardType(.decimalPad)
                .textFieldStyle(LCDFieldStyle())
            MainButton(title: "Enregistrer le plein", role: .primary) { savePlein() }
            if !msg.isEmpty { Text(msg).font(.footnote).foregroundColor(Theme.muted) }
        }
        .padding(14).background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var calibCard: some View {
        let vrais = obd.state.pleins.filter { $0.reel != nil }
        let moy: Double? = {
            let tL = vrais.reduce(0) { $0 + $1.litres }
            let tKm = vrais.reduce(0) { $0 + ($1.km ?? 0) }
            return tKm > 0 ? tL / tKm * 100 : nil
        }()
        return VStack(alignment: .leading, spacing: 6) {
            kv("Conso moyenne réelle",
               moy.map { String(format: "%.1f L/100", $0) } ?? "après 2 pleins")
            kv("Depuis le dernier plein",
               String(format: "%.0f km · %.1f L", obd.state.km, obd.state.litresCalc))
            kv("Facteur de calibration", String(format: "%.3f", obd.state.facteur))
            if let p = vrais.first(where: { $0.prix != nil }), let r = p.reel, let x = p.prix {
                kv("Coût au dernier plein", String(format: "%.2f €/100 km", r * x))
            }
        }
        .padding(14).background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pleinsList: some View {
        VStack(spacing: 0) {
            ForEach(obd.state.pleins.prefix(10)) { p in
                row(p)
                Divider().background(Theme.line)
            }
        }
    }

    private func row(_ p: Plein) -> some View {
        let date = ISO8601DateFormatter().date(from: p.date) ?? Date()
        let df = DateFormatter(); df.dateStyle = .short; df.locale = Locale(identifier: "fr_FR")
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(df.string(from: date)) · \(fmt(p.litres, 2)) L").font(.footnote)
                Text(subText(p)).font(.caption).foregroundColor(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(p.reel.map { fmt($0, 1) } ?? "départ")
                    .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                Text(p.reel != nil ? "L/100" : "").font(.caption2).foregroundColor(Theme.muted)
            }
        }.padding(.vertical, 10)
    }

    private func subText(_ p: Plein) -> String {
        let fuel = Fuels.by(p.carbu).name + " · "
        if let r = p.reel, let km = p.km, let c = p.calc {
            return "\(fuel)\(Int(km)) km · calculé \(fmt(c, 1))\(p.calibre ? "" : " · non calibré")"
        }
        return fuel + "premier plein"
    }

    private func fuelBtn(_ id: String, _ label: String) -> some View {
        let on = obd.state.carbu == id
        return Button { obd.setFuel(id) } label: {
            Text(label).frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundColor(on ? Theme.lcd : Theme.fg)
                .background(on ? Color(red: 0.141, green: 0.078, blue: 0.043) : Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.lcd : Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundColor(Theme.muted)
            Spacer()
            Text(v).monospacedDigit()
        }
    }

    private func fmt(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }

    private func savePlein() {
        let l = Double(litres.replacingOccurrences(of: ",", with: ".")) ?? -1
        guard l > 0 && l < 60 else { msg = "Entre les litres affichés sur la pompe (1 à 60)."; return }
        let px = Double(prix.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0.2 && $0 < 4 ? $0 : nil }
        msg = obd.savePlein(litres: l, prix: px)
        litres = ""; prix = ""
    }
}

struct LCDFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 26, weight: .semibold)).monospacedDigit()
            .padding(12)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
