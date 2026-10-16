import Foundation

/// On-device JSON cache of Game Coordinator item inspections (float / seed /
/// stickers), keyed by asset id. Zero-trust: recorded locally, never sent.
/// Persisting it means the exact float is not re-fetched on every launch.
public struct ItemInspectionStore: Sendable {
    public static let shared = ItemInspectionStore()

    private let cacheURL: URL?

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
    }

    /// Full cache, keyed by asset id.
    public func all() -> [String: GCItemInspection] { load() }

    public func inspection(forAssetID assetID: String) -> GCItemInspection? {
        load()[assetID]
    }

    public var count: Int { load().count }

    /// Merges freshly fetched inspections, overwriting per asset id.
    public func merge(_ inspections: [GCItemInspection]) {
        guard !inspections.isEmpty else { return }
        var cache = load()
        for inspection in inspections {
            cache[inspection.assetID] = inspection
        }
        save(cache)
    }

    /// Drops cached entries whose asset id is no longer in the inventory.
    public func prune(keepingAssetIDs ids: Set<String>) {
        let cache = load()
        let pruned = cache.filter { ids.contains($0.key) }
        if pruned.count != cache.count { save(pruned) }
    }

    public func removeAll() { save([:]) }

    // MARK: - Persistence

    private func load() -> [String: GCItemInspection] {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: GCItemInspection].self, from: data)) ?? [:]
    }

    private func save(_ cache: [String: GCItemInspection]) {
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func defaultCacheURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("gc-item-inspections.json")
    }
}
