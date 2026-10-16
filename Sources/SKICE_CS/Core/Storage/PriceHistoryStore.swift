import Foundation

/// A localized trend summary over a rolling window of Steam Market price snapshots.
public struct PriceTrend: Sendable, Equatable {
    /// Window length in days.
    public let days: Int
    /// Chronological samples within the window (oldest first).
    public let samples: [PriceEntry]
    /// Representative value of the newest sample (median, else lowest).
    public let latest: Decimal
    /// Representative value of the oldest in-window sample, nil with fewer than two samples.
    public let baseline: Decimal?
    /// Percentage change (latest - baseline) / baseline * 100, nil when no baseline.
    public let changePercent: Decimal?

    public init(days: Int, samples: [PriceEntry], latest: Decimal, baseline: Decimal?, changePercent: Decimal?) {
        self.days = days
        self.samples = samples
        self.latest = latest
        self.baseline = baseline
        self.changePercent = changePercent
    }

    /// Absolute change in EUR since the baseline, nil when no baseline.
    public var absoluteChange: Decimal? {
        baseline.map { latest - $0 }
    }

    /// Sparkline input as Double values, oldest first.
    public var sparklineValues: [Double] {
        samples.map { NSDecimalNumber(decimal: $0.displayValue).doubleValue }
    }

    /// True when the trend is strictly upward.
    public var isRising: Bool { changePercent.map { $0 > 0 } ?? false }
    /// True when the trend is strictly downward.
    public var isFalling: Bool { changePercent.map { $0 < 0 } ?? false }
}

/// Rolling local time-series of Steam Community Market EUR price snapshots per
/// market_hash_name, persisted as JSON in the caches directory. Zero-trust and
/// offline-friendly: data is recorded on-device only and never leaves the app.
///
/// One sample is kept per calendar day; samples older than ~30 days are pruned.
public struct PriceHistoryStore: Sendable {
    public static let shared = PriceHistoryStore()

    /// Retention window for a single item's series (~30 days).
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// Safety cap on retained samples per item (one per day plus headroom).
    public static let maxPointsPerName = 32

    private let cacheURL: URL?

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
    }

    // MARK: - Recording

    /// Appends freshly fetched price entries to the rolling series. Multiple
    /// refreshes on the same calendar day coalesce into a single (latest) sample.
    public func record(_ entries: [String: PriceEntry]) {
        guard !entries.isEmpty else { return }
        var series = load()
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.retention)

        for (hash, entry) in entries {
            var points = series[hash] ?? []
            if let last = points.last, DayBucket.string(from: last.fetchedAt) == DayBucket.string(from: entry.fetchedAt) {
                points[points.count - 1] = entry
            } else {
                points.append(entry)
            }
            points = points.filter { $0.fetchedAt >= cutoff }
            if points.count > Self.maxPointsPerName {
                points = Array(points.suffix(Self.maxPointsPerName))
            }
            points.sort { $0.fetchedAt < $1.fetchedAt }
            series[hash] = points
        }

        save(series)
    }

    // MARK: - Reading

    /// Chronological samples recorded for a single item.
    public func history(for marketHashName: String) -> [PriceEntry] {
        load()[marketHashName] ?? []
    }

    /// Full in-memory series, keyed by market_hash_name.
    public func series() -> [String: [PriceEntry]] {
        load()
    }

    // MARK: - Derived

    /// Trend over the last [days] days for a single item, or nil when no sample exists.
    public func trend(for marketHashName: String, days: Int) -> PriceTrend? {
        Self.trend(from: history(for: marketHashName), days: days)
    }

    /// Pure trend computation over a set of samples. Baseline is the oldest sample
    /// inside the window; fewer than two samples yields no delta.
    public static func trend(from samples: [PriceEntry], days: Int, now: Date = Date()) -> PriceTrend? {
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let window = samples
            .filter { $0.fetchedAt >= cutoff }
            .sorted { $0.fetchedAt < $1.fetchedAt }

        guard let newest = window.last else { return nil }
        let latest = newest.displayValue

        guard window.count >= 2, let oldest = window.first else {
            return PriceTrend(days: days, samples: window, latest: latest, baseline: nil, changePercent: nil)
        }

        let baseline = oldest.displayValue
        let changePercent: Decimal? = baseline != 0
            ? (latest - baseline) / baseline * 100
            : nil

        return PriceTrend(days: days, samples: window, latest: latest, baseline: baseline, changePercent: changePercent)
    }

    // MARK: - Persistence

    private func load() -> [String: [PriceEntry]] {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [PriceEntry]].self, from: data)) ?? [:]
    }

    private func save(_ series: [String: [PriceEntry]]) {
        guard let cacheURL, let data = try? JSONEncoder().encode(series) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func defaultCacheURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("steam-price-history.json")
    }

}
