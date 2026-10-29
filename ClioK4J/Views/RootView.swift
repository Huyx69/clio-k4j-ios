import SwiftUI

/// Vue racine à onglets : Route, Diag, Pleins, Trajets.
struct RootView: View {
    @StateObject var obd = OBDManager.shared
    @State private var tab = 0
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                TabView(selection: $tab) {
                    RouteView().tag(0)
                    DiagView().tag(1)
                    PleinsView().tag(2)
                    TrajetsView().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomNav
            }
            if obd.pickerVisible { DevicePickerSheet() }
        }
        .environmentObject(obd)
        .foregroundColor(Theme.fg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLIO 2 · K4J").font(.system(size: 20, weight: .bold)).tracking(0.8)
                Text("1.4 16V · \(Fuels.by(obd.state.carbu).name)")
                    .font(.caption).tracking(0.6).foregroundColor(Theme.muted)
            }
            Spacer()
            Pill(level: obd.connLevel, text: obd.connStatus)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Rectangle().fill(Theme.bg).overlay(Divider().background(Theme.line), alignment: .bottom))
    }

    private var bottomNav: some View {
        HStack(spacing: 0) {
            tabBtn("Route", 0)
            tabBtn("Diag", 1)
            tabBtn("Pleins", 2)
            tabBtn("Trajets", 3)
        }
        .padding(.vertical, 6)
        .background(Theme.panel)
        .overlay(Divider().background(Theme.line), alignment: .top)
    }

    private func tabBtn(_ title: String, _ i: Int) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 4) {
                if tab == i { Rectangle().fill(Theme.lcd).frame(height: 2) }
                else { Color.clear.frame(height: 2) }
                Text(title.uppercased())
                    .font(.system(size: 15, weight: .semibold)).tracking(0.9)
                    .foregroundColor(tab == i ? Theme.lcd : Theme.muted)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct DevicePickerSheet: View {
    @EnvironmentObject var obd: OBDManager
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { obd.pickerVisible = false; obd.ble.stopScan() }
            VStack(spacing: 12) {
                SectionTitle(text: "Boîtiers détectés")
                if obd.discovered.isEmpty {
                    Text("Recherche en cours…").foregroundColor(Theme.muted)
                        .padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(obd.discovered, id: \.identifier) { p in
                                Button { obd.connect(p) } label: {
                                    HStack {
                                        Text(p.name ?? "sans nom")
                                        Spacer()
                                        Text("se connecter").foregroundColor(Theme.lcd)
                                    }
                                    .padding()
                                    .background(Theme.panel)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .foregroundColor(Theme.fg)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
                MainButton(title: "Annuler", role: .secondary) {
                    obd.pickerVisible = false; obd.ble.stopScan()
                }
            }
            .padding(20)
            .background(Theme.bg.overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(20)
        }
    }
}
