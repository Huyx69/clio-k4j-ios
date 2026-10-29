import Foundation

/// Moteur K4J 1.4 16v, Clio 2 phase 2 (2001-2003).
enum K4J {
    static let cyl: Double = 1.390        // Cylindrée (L)
    static let ve: Double = 0.80          // Rendement volumétrique
    static let lambdaFull: Double = 0.87  // Richesse à pleine charge
    static let R: Double = 287.05         // Constante spéc. air (J/kg·K)
    static let redline: Double = 6250     // Zone rouge (tr/min)
}

struct Fuel: Identifiable, Hashable {
    let id: String
    let name: String
    let afr: Double   // Rapport air/carburant stœchio
    let density: Double // g/L
}

enum Fuels {
    static let all: [Fuel] = [
        Fuel(id: "E85",  name: "E85",            afr: 9.8,  density: 785),
        Fuel(id: "MIX",  name: "Mélange E85+SP", afr: 11.8, density: 767),
        Fuel(id: "SP95", name: "SP95-E10",       afr: 14.1, density: 750),
        Fuel(id: "SP98", name: "SP98",           afr: 14.5, density: 745),
    ]
    static func by(_ id: String) -> Fuel { all.first { $0.id == id } ?? all[0] }
}
