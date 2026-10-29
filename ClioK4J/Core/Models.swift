import Foundation

struct LiveData: Equatable {
    var rpm: Double?
    var vit: Double?       // km/h
    var map: Double?       // kPa
    var pap: Double?       // % papillon
    var stft: Double?      // %
    var ltft: Double?      // %
    var eau: Double?       // °C
    var air: Double?       // °C
    var charge: Double?    // %
    var av: Double?        // ° avance
    var o2: Double?        // V
    var bat: Double?       // V
    var lh: Double = 0     // L/h calculé
}

struct TripPoint: Codable, Equatable {
    let s: Int             // secondes depuis début
    let rpm: Double?
    let vit: Double?
    let map: Double?
    let pap: Double?
    let eau: Double?
    let stft: Double?
    let ltft: Double?
    let bat: Double?
    let lh: Double
}

struct TripRecord: Codable, Identifiable, Equatable {
    var id: Double { debut }
    let debut: Double
    let fin: Double
    let km: Double
    let litres: Double
    let maxRpm: Int
    let maxEau: Int
    let demo: Bool
    let pts: [TripPoint]
    let trou: Int
    let carbu: String
}

struct Plein: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let litres: Double
    let km: Double?
    let reel: Double?
    let calc: Double?
    let calibre: Bool
    let depart: Bool
    let carbu: String
    let prix: Double?
}

struct AppState: Codable, Equatable {
    var facteur: Double = 1
    var litresCalc: Double = 0
    var km: Double = 0
    var incomplet: Bool = false
    var carbu: String = "E85"
    var pleins: [Plein] = []
    var trajets: [TripRecord] = []
}

/// Code défaut OBD-II décodé
struct DTC: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let desc: String
    let pending: Bool
}
