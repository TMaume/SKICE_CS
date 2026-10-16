import Foundation
import Observation

/// Fetches the player's CS2 ranking from the Game Coordinator (Tier B), records
/// Premier rating snapshots locally, and caches the latest ranking so the card
/// renders the last known value instantly on launch.
@Observable
@MainActor
public final class RankViewModel {
    public private(set) var currentRanking: PlayerRankingInfo?
    public private(set) var history: [RatingSnapshot] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    /// When the ranking was last refreshed from the Game Coordinator.
    public private(set) var lastUpdated: Date?

    /// True when the rating should be auto-refreshed: never refreshed yet, or
    /// the last refresh is older than one hour.
    public var shouldAutoRefresh: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) >= 3_600
    }

    private let client: GameCoordinatorClient
    private let store: RatingSnapshotStore

    private static func rankingCacheKey(_ steamID64: String) -> String {
        "com.dtl21.SKICEcs.cachedRanking.v1." + steamID64
    }

    private static func updatedAtCacheKey(_ steamID64: String) -> String {
        "com.dtl21.SKICEcs.cachedRankingUpdatedAt.v1." + steamID64
    }

    public init(
        client: GameCoordinatorClient = .shared,
        store: RatingSnapshotStore = .shared
    ) {
        self.client = client
        self.store = store
    }

    /// Loads the on-device rating history plus the last cached ranking, so the
    /// card shows stale-but-real data before any network round trip.
    public func loadHistory(for steamID64: String?) {
        guard let steamID64, !steamID64.isEmpty else {
            history = []
            currentRanking = nil
            lastUpdated = nil
            return
        }
        history = store.loadSnapshots(for: steamID64)
        if let data = UserDefaults.standard.data(forKey: Self.rankingCacheKey(steamID64)) {
            currentRanking = try? JSONDecoder().decode(PlayerRankingInfo.self, from: data)
        }
        lastUpdated = UserDefaults.standard.object(forKey: Self.updatedAtCacheKey(steamID64)) as? Date
    }

    public func refresh(steamID64: String, refreshToken: String) async {
        guard !isLoading else { return }
        guard let steamID = UInt64(steamID64) else {
            errorMessage = "No valid SteamID64 for the GC session."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let entries = try await client.fetchPlayerRanking(steamID64: steamID, refreshToken: refreshToken)
            let premier = entries.first(where: { $0.isPremier }) ?? entries.first
            if let premier {
                currentRanking = premier
                store.record(steamID64: steamID64, ranking: premier)
                if let data = try? JSONEncoder().encode(premier) {
                    UserDefaults.standard.set(data, forKey: Self.rankingCacheKey(steamID64))
                }
            }
            history = store.loadSnapshots(for: steamID64)
            lastUpdated = .now
            UserDefaults.standard.set(lastUpdated, forKey: Self.updatedAtCacheKey(steamID64))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
