import Foundation

/// One recorded Premier rating, captured on-device after a GC rank refresh.
public struct RatingSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let steamID64: String
    public let rating: Int
    public let rankChange: Float
    public let rankTypeID: UInt32
    public let wins: UInt32
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        steamID64: String,
        rating: Int,
        rankChange: Float,
        rankTypeID: UInt32,
        wins: UInt32,
        timestamp: Date = .now
    ) {
        self.id = id
        self.steamID64 = steamID64
        self.rating = rating
        self.rankChange = rankChange
        self.rankTypeID = rankTypeID
        self.wins = wins
        self.timestamp = timestamp
    }
}

/// Persists the local Premier-rating history (one snapshot per rating change),
/// mirroring StatsSnapshotStore's on-device, zero-trust model.
@MainActor
public final class RatingSnapshotStore {
    public static let shared = RatingSnapshotStore()

    private let storageKeyPrefix = "com.dtl21.SKICEcs.ratingSnapshots.v1."
    private let maxSnapshotsPerUser = 180

    private init() {}

    /// Records a snapshot only when the rating differs from the last recorded
    /// one, so the history holds meaningful change points rather than repeats.
    public func record(steamID64: String, ranking: PlayerRankingInfo, timestamp: Date = .now) {
        guard !steamID64.isEmpty, let rating = ranking.premierRating else { return }

        var snapshots = loadSnapshots(for: steamID64)
        if let last = snapshots.last, last.rating == rating { return }

        snapshots.append(
            RatingSnapshot(
                steamID64: steamID64,
                rating: rating,
                rankChange: ranking.rankChange,
                rankTypeID: ranking.rankTypeID,
                wins: ranking.wins,
                timestamp: timestamp
            )
        )
        snapshots.sort { $0.timestamp < $1.timestamp }
        if snapshots.count > maxSnapshotsPerUser {
            snapshots = Array(snapshots.suffix(maxSnapshotsPerUser))
        }
        saveSnapshots(snapshots, for: steamID64)
    }

    public func loadSnapshots(for steamID64: String) -> [RatingSnapshot] {
        guard !steamID64.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKeyPrefix + steamID64) else {
            return []
        }
        return (try? JSONDecoder().decode([RatingSnapshot].self, from: data)) ?? []
    }

    public func clearSnapshots(for steamID64: String) {
        guard !steamID64.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: storageKeyPrefix + steamID64)
    }

    private func saveSnapshots(_ snapshots: [RatingSnapshot], for steamID64: String) {
        guard !steamID64.isEmpty, let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKeyPrefix + steamID64)
    }
}
