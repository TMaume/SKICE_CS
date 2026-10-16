import Foundation
import Observation

/// Fetches the player's CS2 ranking from the Game Coordinator (Tier B) and
/// records Premier rating snapshots locally. Read-only: it only decodes the
/// GC's own account-data messages.
@Observable
@MainActor
public final class RankViewModel {
    public private(set) var currentRanking: PlayerRankingInfo?
    public private(set) var history: [RatingSnapshot] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let client: GameCoordinatorClient
    private let store: RatingSnapshotStore

    public init(
        client: GameCoordinatorClient = .shared,
        store: RatingSnapshotStore = .shared
    ) {
        self.client = client
        self.store = store
    }

    public func loadHistory(for steamID64: String?) {
        guard let steamID64, !steamID64.isEmpty else {
            history = []
            return
        }
        history = store.loadSnapshots(for: steamID64)
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
            }
            history = store.loadSnapshots(for: steamID64)
            if entries.isEmpty {
                errorMessage = "The Game Coordinator returned no ranking data."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
