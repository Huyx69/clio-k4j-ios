import SwiftUI
import UniformTypeIdentifiers

struct TrajetsView: View {
    @EnvironmentObject var obd: OBDManager
    @State private var selected: TripRecord?
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var msg: String = "Tes données restent dans l'app. Exporte une sauvegarde de temps en temps."

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(text: "Trajets")
                if let s = selected { detailCard(s) }
                if obd.state.trajets.isEmpty {
                    Text("Aucun trajet pour l'instant. Connecte le boîtier et roule, ou essaie le mode démo.")
                        .font(.footnote).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    tripList
                }
                HStack(spacing: 10) {
                    MainButton(title: "Exporter la sauvegarde", role: .secondary) { exportBackup() }
                    MainButton(title: "Importer", role: .secondary) { showImporter = true }
                }
                Text(msg).font(.footnote).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDoc,
                      contentType: .json,
                      defaultFilename: "clio-k4j-sauvegarde") { _ in }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { res in
            if case .success(let url) = res,
               let data = try? Data(contentsOf: url),
               let s = Storage.shared.restore(data) {
                obd.state = s
                obd.save()
                msg = "Sauvegarde importée."
            } else {
                msg = "Ce fichier n'est pas une sauvegarde de cette app."
            }
        }
    }

    private var tripList: some View {
        VStack(spacing: 0) {
            ForEach(obd.state.trajets) { t in
                Button { selected = t } label: { tripRow(t) }
                    .foregroundColor(Theme.fg)
                Divider().background(Theme.line)
            }
        }
    }

    private func tripRow(_ t: TripRecord) -> some View {
        let d = Date(timeIntervalSince1970: t.debut)
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short; df.locale = Locale(identifier: "fr_FR")
        let min = Int((t.fin - t.debut) / 60)
        let l100 = t.km > 0.3 ? String(format: "%.1f", t.litres / t.km * 100) : "--"
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(df.string(from: d)) · \(min) min\(t.demo ? " · démo" : "")").font(.footnote)
                Text("\(String(format: "%.1f", t.km)) km · \(String(format: "%.2f", t.litres)) L · \(t.maxRpm) tr/min max · \(Fuels.by(t.carbu).name)\(t.trou > 60 ? " · \(t.trou/60) min non enreg." : "")")
                    .font(.caption).foregroundColor(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(l100).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                Text("L/100").font(.caption2).foregroundColor(Theme.muted)
            }
        }.padding(.vertical, 10)
    }

    private func detailCard(_ t: TripRecord) -> some View {
        let d = Date(timeIntervalSince1970: t.debut)
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short; df.locale = Locale(identifier: "fr_FR")
        return VStack(spacing: 10) {
            HStack {
                SectionTitle(text: df.string(from: d))
                Button("Fermer") { selected = nil }.foregroundColor(Theme.lcd)
            }
            TripChart(points: t.pts).frame(height: 320)
            MainButton(title: "Exporter en CSV", role: .secondary) { exportCSV(t) }
        }
        .padding(14).background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func exportBackup() {
        exportDoc = BackupDocument(data: Storage.shared.backupData(obd.state))
        showExporter = true
    }

    private func exportCSV(_ t: TripRecord) {
        let head = "secondes;regime;vitesse;admission_kPa;papillon;eau;corr_courte;corr_longue;batterie;conso_L_h\n"
        let rows = t.pts.map { p -> String in
            func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "" }
            return "\(p.s);\(f(p.rpm));\(f(p.vit));\(f(p.map));\(f(p.pap));\(f(p.eau));\(f(p.stft));\(f(p.ltft));\(f(p.bat));\(String(format: "%.2f", p.lh).replacingOccurrences(of: ".", with: ","))"
        }.joined(separator: "\n")
        let data = (head + rows).data(using: .utf8) ?? Data()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trajet_\(Int(t.debut)).csv")
        try? data.write(to: tmp)
        presentShare(tmp)
    }

    private func presentShare(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(vc, animated: true)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Graphique vitesse / régime / conso dessiné avec Canvas natif.
struct TripChart: View {
    let points: [TripPoint]
    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else {
                ctx.draw(Text("Trajet trop court").foregroundColor(Theme.muted),
                         at: CGPoint(x: 20, y: 20), anchor: .topLeading)
                return
            }
            let W = size.width, H = size.height
            let tMax = Double(points.last?.s ?? 1)
            let ph = H / 3
            struct Serie { let label: String; let color: Color; let max: Double; let get: (TripPoint) -> Double? }
            let maxSpeed = max(1, points.compactMap { $0.vit }.max() ?? 1) * 1.1
            let maxRpm   = max(1, points.compactMap { $0.rpm }.max() ?? 1) * 1.1
            let series: [Serie] = [
                Serie(label: "Vitesse km/h", color: Theme.ok,   max: maxSpeed, get: { $0.vit }),
                Serie(label: "Régime tr/min", color: Theme.warn, max: maxRpm,   get: { $0.rpm }),
                Serie(label: "Conso L/100",   color: Theme.lcd, max: 30,        get: {
                    guard let v = $0.vit, v > 5 else { return nil }
                    return $0.lh / v * 100
                }),
            ]
            for (i, s) in series.enumerated() {
                let y0 = CGFloat(i) * ph + ph - 14
                let y1 = CGFloat(i) * ph + 28
                var path = Path()
                var on = false
                for p in points {
                    guard let v = s.get(p) else { on = false; continue }
                    let x = CGFloat(50 + Double(p.s) / tMax * Double(W - 60))
                    let y = y0 - CGFloat(min(v, s.max) / s.max) * (y0 - y1)
                    if on { path.addLine(to: CGPoint(x: x, y: y)) }
                    else  { path.move(to: CGPoint(x: x, y: y)); on = true }
                }
                ctx.stroke(path, with: .color(s.color), lineWidth: 2.5)
                ctx.draw(Text(s.label).font(.caption).foregroundColor(Theme.muted),
                         at: CGPoint(x: 50, y: CGFloat(i) * ph + 10), anchor: .topLeading)
            }
        }
        .background(Theme.bg)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
