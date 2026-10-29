import Foundation

/// Persistance de l'état sous un fichier JSON unique dans Application Support.
final class Storage {
    static let shared = Storage()
    private let fileName = "clioK4J.v1.json"

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    func load() -> AppState {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return s
    }

    func save(_ s: AppState) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func backupData(_ s: AppState) -> Data {
        (try? JSONEncoder().encode(s)) ?? Data()
    }

    func restore(_ data: Data) -> AppState? {
        try? JSONDecoder().decode(AppState.self, from: data)
    }
}
