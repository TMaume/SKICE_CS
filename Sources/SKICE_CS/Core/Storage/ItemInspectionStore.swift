import Foundation

/// On-device JSON cache of Game Coordinator item inspections (float / seed /
/// stickers), keyed by asset id. Zero-trust: recorded locally, never sent.
/// Persisting it means the exact float is not re-fetched on every launch.
public struct ItemInspectionStore: Sendable {
    public static let shared = ItemInspectionStore()

    private let cache: JSONFileCache<[String: GCItemInspection]>

    public init(cacheURL: URL? = nil) {
        if let cacheURL {
            cache = JSONFileCache(fileURL: cacheURL)
        } else {
            cache = JSONFileCache(fileName: "gc-item-inspections.json")
        }
    }

    /// Full cache, keyed by asset id.
    public func all() -> [String: GCItemInspection] { cache.load() ?? [:] }

    public func inspection(forAssetID assetID: String) -> GCItemInspection? {
        cache.load()?[assetID]
    }

    public var count: Int { cache.load()?.count ?? 0 }

    /// Merges freshly fetched inspections, overwriting per asset id.
    public func merge(_ inspections: [GCItemInspection]) {
        guard !inspections.isEmpty else { return }
        var merged = cache.load() ?? [:]
        for inspection in inspections {
            merged[inspection.assetID] = inspection
        }
        cache.save(merged)
    }

    /// Drops cached entries whose asset id is no longer in the inventory.
    public func prune(keepingAssetIDs ids: Set<String>) {
        let current = cache.load() ?? [:]
        let pruned = current.filter { ids.contains($0.key) }
        if pruned.count != current.count { cache.save(pruned) }
    }

    public func removeAll() { cache.save([:]) }
}
