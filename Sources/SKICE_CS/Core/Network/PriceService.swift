import Foundation

/// A single item's Steam Community Market price snapshot (EUR).
public struct PriceEntry: Codable, Sendable, Hashable {
    /// Lowest current listing ("min" price).
    public let lowest: Decimal
    /// Median sale price over Steam's recent window, when reported.
    public let median: Decimal?
    /// Number of listings/sales Steam reports, when present.
    public let volume: Int?
    public let fetchedAt: Date

    public init(lowest: Decimal, median: Decimal?, volume: Int?, fetchedAt: Date) {
        self.lowest = lowest
        self.median = median
        self.volume = volume
        self.fetchedAt = fetchedAt
    }

    /// Single representative value for portfolio math: median when available, else lowest.
    public var displayValue: Decimal { median ?? lowest }
}

/// A menu of Steam Market prices keyed by \`market_hash_name\`.
public struct PriceTable: Codable, Sendable {
    public let entries: [String: PriceEntry]
    public let fetchedAt: Date

    public static let empty = PriceTable(entries: [:], fetchedAt: .distantPast)

    public init(entries: [String: PriceEntry], fetchedAt: Date) {
        self.entries = entries
        self.fetchedAt = fetchedAt
    }

    /// True once the table is older than the cache lifetime (~24h).
    public var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > PriceService.cacheTTL
    }

    /// True when every requested hash already has an entry.
    public func covers(_ hashes: Set<String>) -> Bool {
        hashes.allSatisfy { entries[$0] != nil }
    }

    public func entry(for marketHashName: String) -> PriceEntry? {
        entries[marketHashName]
    }
}

/// Transport/source errors raised by \`PriceService\`.
public enum PriceServiceError: LocalizedError, Sendable {
    case badStatus(Int)
    case decoding(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Steam Market price request failed (HTTP \(code))."
        case .decoding(let details):
            return "Failed to parse Steam Market price response: \(details)"
        case .network(let details):
            return "Network error while fetching Steam Market prices: \(details)"
        }
    }
}

/// Fetches Steam Community Market prices (EUR) for a set of \`market_hash_name\`
/// values and caches the result locally for ~24h.
///
/// Steam exposes no bulk price endpoint, so each distinct owned item is queried
/// individually through \`APIClient\` (retry/backoff honoring \`Retry-After\`),
/// with bounded concurrency and a small politeness delay. Scope is intentionally
/// limited to the items actually present in the user's inventory.
public struct PriceService: Sendable {
    public static let shared = PriceService()

    /// Cache lifetime for the on-disk price table (~24h).
    public static let cacheTTL: TimeInterval = 24 * 60 * 60

    /// Steam currency code: 3 = EUR.
    private let currencyCode = 3
    private let appID = 730
    /// Steam's market UI requires a real browser-ish User-Agent.
    private let userAgent = "SKICE_CS/1.0 (personal CS2 companion; +https://github.com/TMaume/SKICE_CS)"
    /// Concurrent in-flight price requests (kept modest to respect Steam limits).
    private let concurrency = 6
    /// Safety cap on distinct items priced per refresh pass.
    private let maxItemsPerRefresh = 400
    private let politenessDelay: Duration = .milliseconds(150)

    private let client: APIClient
    private let cacheURL: URL?

    public init(session: URLSession = .shared) {
        self.client = APIClient(session: session)
        self.cacheURL = Self.defaultCacheURL()
    }

    // MARK: - Public API

    /// Returns a price table covering \`hashes\`, fetching only what the cache is
    /// missing (or everything, when stale / forced). Never throws on individual
    /// item failures — those simply stay absent ("—" in the UI).
    public func loadPriceTable(for hashes: Set<String>, forceRefresh: Bool = false) async throws -> PriceTable {
        let requested = Set(hashes.filter { !$0.isEmpty })
        let cached = loadCachedTable() ?? .empty

        let missing = requested.subtracting(cached.entries.keys)
        let needsFullRefresh = forceRefresh || cached.isStale
        let toFetch = needsFullRefresh ? requested : missing
        let capped = Array(toFetch).prefix(maxItemsPerRefresh)

        guard !capped.isEmpty else { return cached }

        var fetched: [String: PriceEntry] = [:]
        for chunk in Array(capped).chunked(into: concurrency) {
            let pairs = await withTaskGroup(of: (String, PriceEntry?).self) { group -> [(String, PriceEntry?)] in
                for hash in chunk {
                    group.addTask { (hash, await self.fetchPrice(for: hash)) }
                }
                var acc: [(String, PriceEntry?)] = []
                for await pair in group { acc.append(pair) }
                return acc
            }
            for (hash, entry) in pairs where entry != nil { fetched[hash] = entry }
            try? await Task.sleep(for: politenessDelay)
        }

        let pricedCount = fetched.count
        if pricedCount < capped.count {
            DebugLogger.shared.info(
                "Steam prices: \(pricedCount)/\(capped.count) items priced this pass.",
                category: "Price"
            )
        }

        // If nothing resolved (offline / fully rate-limited), keep the previous
        // table rather than stamping a fresh-but-empty cache.
        guard !fetched.isEmpty else { return cached }

        var merged = cached.entries
        for (hash, entry) in fetched { merged[hash] = entry }
        let updated = PriceTable(entries: merged, fetchedAt: Date())
        saveCachedTable(updated)
        return updated
    }

    // MARK: - Single item fetch

    private func fetchPrice(for marketHashName: String) async -> PriceEntry? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "steamcommunity.com"
        components.path = "/market/priceoverview/"
        components.queryItems = [
            URLQueryItem(name: "appid", value: String(appID)),
            URLQueryItem(name: "currency", value: String(currencyCode)),
            URLQueryItem(name: "market_hash_name", value: marketHashName)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")

        let response: APIResponse
        do {
            response = try await client.send(request)
        } catch {
            // Cancellation is expected during teardown/refresh — keep it quiet.
            if Task.isCancelled { return nil }
            DebugLogger.shared.warning(
                "Steam price error for '\(marketHashName)': \(error.localizedDescription)",
                category: "Price"
            )
            return nil
        }

        guard response.statusCode == 200 else {
            DebugLogger.shared.warning(
                "Steam price HTTP \(response.statusCode) for '\(marketHashName)'",
                category: "Price"
            )
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(SteamPriceOverviewResponse.self, from: response.data),
              decoded.success else {
            return nil
        }

        guard let lowest = Self.parseLocalizedPrice(decoded.lowestPrice) else { return nil }
        let median = Self.parseLocalizedPrice(decoded.medianPrice)
        let volume = decoded.volume.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        return PriceEntry(lowest: lowest, median: median, volume: volume, fetchedAt: Date())
    }

    // MARK: - Localised price parsing

    /// Parses a Steam currency string such as "28,37€", "1.234,56€", or "$1.23".
    /// The requested currency (EUR) is formatted with a comma decimal separator.
    static func parseLocalizedPrice(_ raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let filtered = raw.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !filtered.isEmpty else { return nil }

        let lastComma = filtered.lastIndex(of: ",")
        let lastDot = filtered.lastIndex(of: ".")
        let normalized: String

        if let comma = lastComma, let dot = lastDot {
            if comma > dot {
                normalized = filtered.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = filtered.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma = lastComma {
            let trailing = filtered.distance(from: filtered.index(after: comma), to: filtered.endIndex)
            normalized = trailing == 3
                ? filtered.replacingOccurrences(of: ",", with: "")
                : filtered.replacingOccurrences(of: ",", with: ".")
        } else if let dot = lastDot {
            let trailing = filtered.distance(from: filtered.index(after: dot), to: filtered.endIndex)
            normalized = trailing == 3
                ? filtered.replacingOccurrences(of: ".", with: "")
                : filtered
        } else {
            normalized = filtered
        }

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - On-disk cache

    private func loadCachedTable() -> PriceTable? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(PriceTable.self, from: data)
    }

    private func saveCachedTable(_ table: PriceTable) {
        guard let cacheURL, let data = try? JSONEncoder().encode(table) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func defaultCacheURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("steam-price-table.json")
    }
}

// MARK: - Decoding

private struct SteamPriceOverviewResponse: Decodable {
    let success: Bool
    let lowestPrice: String?
    let medianPrice: String?
    let volume: String?

    enum CodingKeys: String, CodingKey {
        case success
        case lowestPrice = "lowest_price"
        case medianPrice = "median_price"
        case volume
    }
}

// MARK: - Formatting

/// Deterministic EUR currency formatting used across inventory price surfaces.
public enum PriceFormatter {
    private static let eur: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.currencySymbol = "€"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public static func eur(_ value: Decimal) -> String {
        eur.string(from: value as NSDecimalNumber) ?? "€\(value)"
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
