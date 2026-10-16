import Foundation

/// A single Codable document persisted as JSON in the app's caches directory.
/// Shared by the on-device stores so load/save/URL logic isn't duplicated.
struct JSONFileCache<Value: Codable> {
    let fileURL: URL?

    /// Backs the cache with a file of the given name in the caches directory.
    init(fileName: String) {
        fileURL = Self.cacheURL(named: fileName)
    }

    /// Backs the cache with an explicit file URL (used by tests).
    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func load() -> Value? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let fileURL, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func cacheURL(named fileName: String) -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }
}
