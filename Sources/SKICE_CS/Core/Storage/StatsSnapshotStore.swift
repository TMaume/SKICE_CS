import Foundation

public struct StatsSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let steamID64: String
    public let timestamp: Date
    public let dayBucket: String
    public let rawStats: [String: Int]

    public init(
        id: UUID = UUID(),
        steamID64: String,
        timestamp: Date = .now,
        rawStats: [String: Int]
    ) {
        self.id = id
        self.steamID64 = steamID64
        self.timestamp = timestamp
        self.dayBucket = Self.makeDayBucket(from: timestamp)
        self.rawStats = rawStats
    }

    public static func makeDayBucket(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public struct SnapshotDiffResult: Equatable, Sendable {
    public let stats: SteamPlayerStats
    public let isDeltaActive: Bool
    public let referenceDate: Date?
    public let earliestSnapshotDate: Date?
}

@MainActor
public final class StatsSnapshotStore {
    public static let shared = StatsSnapshotStore()

    private let storageKeyPrefix = "com.dtl21.SKICEcs.statsSnapshots.v4."
    private let maxSnapshotsPerUser = 90

    private init() {}

    // MARK: - Snapshot Recording

    public func recordSnapshot(steamID64: String, rawStats: [String: Int], timestamp: Date = .now) {
        guard !steamID64.isEmpty, !rawStats.isEmpty else { return }

        var snapshots = loadSnapshots(for: steamID64)
        let currentBucket = StatsSnapshot.makeDayBucket(from: timestamp)

        if snapshots.isEmpty {
            let initial = StatsSnapshot(steamID64: steamID64, timestamp: timestamp, rawStats: rawStats)
            snapshots.append(initial)
        } else if let lastIndex = snapshots.indices.last {
            if snapshots.count == 1 && snapshots[0].dayBucket == currentBucket {
                let firstStats = snapshots[0].rawStats
                let currentKills = rawStats["total_kills"] ?? 0
                let baselineKills = firstStats["total_kills"] ?? 0
                if currentKills > baselineKills {
                    let latest = StatsSnapshot(steamID64: steamID64, timestamp: timestamp, rawStats: rawStats)
                    snapshots.append(latest)
                }
            } else if snapshots[lastIndex].dayBucket == currentBucket && snapshots.count > 1 {
                snapshots[lastIndex] = StatsSnapshot(
                    id: snapshots[lastIndex].id,
                    steamID64: steamID64,
                    timestamp: timestamp,
                    rawStats: rawStats
                )
            } else {
                let next = StatsSnapshot(steamID64: steamID64, timestamp: timestamp, rawStats: rawStats)
                snapshots.append(next)
            }
        }

        snapshots.sort { $0.timestamp < $1.timestamp }
        if snapshots.count > maxSnapshotsPerUser {
            let earliest = snapshots.first!
            let tail = Array(snapshots.suffix(maxSnapshotsPerUser - 1))
            snapshots = [earliest] + tail
        }

        saveSnapshots(snapshots, for: steamID64)
    }

    // MARK: - Timeframe Diffing

    public func resolveStats(
        latestStats: SteamPlayerStats,
        timeframe: StatsTimeFrame,
        customStartDate: Date,
        customEndDate: Date
    ) -> SnapshotDiffResult {
        let snapshots = loadSnapshots(for: latestStats.steamID64)
        let earliestDate = snapshots.first?.timestamp

        guard timeframe != .allTime else {
            return SnapshotDiffResult(
                stats: latestStats,
                isDeltaActive: false,
                referenceDate: nil,
                earliestSnapshotDate: earliestDate
            )
        }

        let targetWindow = timeframe.dateInterval(customStart: customStartDate, customEnd: customEndDate)
        guard !snapshots.isEmpty else {
            return SnapshotDiffResult(
                stats: latestStats,
                isDeltaActive: false,
                referenceDate: nil,
                earliestSnapshotDate: nil
            )
        }

        let candidateBeforeStart = snapshots
            .filter { $0.timestamp <= targetWindow.start }
            .max(by: { $0.timestamp < $1.timestamp })

        let baselineSnapshot = candidateBeforeStart ?? snapshots.first!

        var deltaMap: [String: Int] = [:]
        deltaMap.reserveCapacity(latestStats.rawCounters.count)

        for (key, latestValue) in latestStats.rawCounters {
            if !key.hasPrefix("last_match_") {
                let baseValue = baselineSnapshot.rawStats[key] ?? 0
                deltaMap[key] = max(0, latestValue - baseValue)
            }
        }

        let deltaKills = deltaMap["total_kills"] ?? 0
        let deltaRounds = deltaMap["total_rounds_played"] ?? 0
        let hasMeaningfulDelta = (deltaKills > 0 || deltaRounds > 0) && baselineSnapshot.timestamp < latestStats.fetchedAt

        if hasMeaningfulDelta {
            let diffStats = SteamPlayerStats(
                steamID64: latestStats.steamID64,
                rawCounters: deltaMap,
                fetchedAt: latestStats.fetchedAt
            )
            return SnapshotDiffResult(
                stats: diffStats,
                isDeltaActive: true,
                referenceDate: baselineSnapshot.timestamp,
                earliestSnapshotDate: earliestDate
            )
        } else {
            return SnapshotDiffResult(
                stats: latestStats,
                isDeltaActive: false,
                referenceDate: baselineSnapshot.timestamp,
                earliestSnapshotDate: earliestDate ?? latestStats.fetchedAt
            )
        }
    }

    public func clearSnapshots(for steamID64: String) {
        guard !steamID64.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: storageKeyPrefix + steamID64)
    }

    public func loadSnapshots(for steamID64: String) -> [StatsSnapshot] {
        guard !steamID64.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKeyPrefix + steamID64) else {
            return []
        }
        return (try? JSONDecoder().decode([StatsSnapshot].self, from: data)) ?? []
    }

    private func saveSnapshots(_ snapshots: [StatsSnapshot], for steamID64: String) {
        guard !steamID64.isEmpty,
              let data = try? JSONEncoder().encode(snapshots) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKeyPrefix + steamID64)
    }
}