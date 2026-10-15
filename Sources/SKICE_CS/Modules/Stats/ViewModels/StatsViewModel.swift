import Foundation
import Observation

@Observable
@MainActor
public final class StatsViewModel {
    // MARK: - Published State

    public private(set) var overviewStats: PlayerOverviewStats?
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var steamErrorMessage: String?
    public private(set) var faceitErrorMessage: String?

    public var selectedFilter: StatsPlatformFilter = .combined
    public var selectedFaction: StatsFactionFilter = .both
    public var selectedTimeFrame: StatsTimeFrame = .allTime
    public var customStartDate: Date = Date.now.addingTimeInterval(-7 * 86_400)
    public var customEndDate: Date = .now

    public var selectedMapForSheet: SteamMapStatSummary?

    // MARK: - Dependencies & Cache

    private let steamService: SteamStatsService
    private let faceitService: FaceitStatsService
    private let snapshotStore: StatsSnapshotStore
    private let cacheKey = "com.dtl21.SKICEcs.cachedPlayerOverviewStats.v4"
    private var hasCompletedInitialAttempt: Bool = false
    private var lastAttemptedSteamID: String?

    public init(
        steamService: SteamStatsService = .shared,
        faceitService: FaceitStatsService = .shared,
        snapshotStore: StatsSnapshotStore = .shared
    ) {
        self.steamService = steamService
        self.faceitService = faceitService
        self.snapshotStore = snapshotStore
        loadCachedStats()
    }

    // MARK: - Computed Timeframe & Snapshot Diff State

    public var currentDiffResult: SnapshotDiffResult? {
        guard let latestSteam = overviewStats?.steamStats else { return nil }
        return snapshotStore.resolveStats(
            latestStats: latestSteam,
            timeframe: selectedTimeFrame,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    public var activeSteamStats: SteamPlayerStats? {
        currentDiffResult?.stats ?? overviewStats?.steamStats
    }

    public var isFaceitConnected: Bool {
        overviewStats?.faceitStats != nil
    }

    public var filteredFaceitMatches: [FaceitMatchSummary] {
        guard let faceit = overviewStats?.faceitStats else { return [] }
        if selectedTimeFrame == .allTime {
            return faceit.recentMatches
        }
        let interval = selectedTimeFrame.dateInterval(
            customStart: customStartDate,
            customEnd: customEndDate
        )
        let matchesInWindow = faceit.matches(in: interval)
        return matchesInWindow.isEmpty ? faceit.recentMatches : matchesInWindow
    }

    public var snapshotStatusBadgeText: String? {
        guard selectedTimeFrame != .allTime else { return nil }
        if let diff = currentDiffResult {
            if diff.isDeltaActive, let refDate = diff.referenceDate {
                return "Since \(refDate.formatted(date: .abbreviated, time: .omitted))"
            } else {
                let sinceDate = diff.earliestSnapshotDate ?? overviewStats?.lastUpdated ?? .now
                return "Tracking since \(sinceDate.formatted(date: .abbreviated, time: .omitted))"
            }
        }
        return nil
    }

    public var isShowingDelta: Bool {
        currentDiffResult?.isDeltaActive ?? false
    }

    // MARK: - Public Actions

    public func loadStatsIfNeeded(explicitSteamID64: String? = nil) async {
        let normalizedID = explicitSteamID64?.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasCompletedInitialAttempt, lastAttemptedSteamID == normalizedID {
            return
        }
        hasCompletedInitialAttempt = true
        lastAttemptedSteamID = normalizedID
        await refreshStats(explicitSteamID64: explicitSteamID64)
    }

    public func refreshStats(explicitSteamID64: String? = nil) async {
        guard !isLoading else { return }

        if overviewStats == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }

        steamErrorMessage = nil
        faceitErrorMessage = nil

        let resolvedSteamID: String
        if let explicit = explicitSteamID64?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            resolvedSteamID = explicit
        } else {
            resolvedSteamID = AppCredentialsStore.readSteamID64()
        }

        let steamKey = AppCredentialsStore.readSteamWebAPIKey()
        let faceitId = AppCredentialsStore.readFaceitIdentifier().trimmingCharacters(in: .whitespacesAndNewlines)
        let faceitKey = AppCredentialsStore.readFaceitAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)

        async let steamResult = fetchSteamSafely(steamID64: resolvedSteamID, apiKey: steamKey)
        async let faceitResult = fetchFaceitSafely(
            identifier: faceitId,
            fallbackSteamID64: resolvedSteamID,
            apiKey: faceitKey
        )

        let (resolvedSteam, resolvedFaceit) = await (steamResult, faceitResult)

        if let freshSteam = resolvedSteam {
            snapshotStore.recordSnapshot(
                steamID64: freshSteam.steamID64,
                rawStats: freshSteam.rawCounters,
                timestamp: freshSteam.fetchedAt
            )
        }

        let mergedSteam = resolvedSteam ?? overviewStats?.steamStats
        let mergedFaceit = faceitKey.isEmpty ? nil : (resolvedFaceit ?? overviewStats?.faceitStats)

        if mergedSteam != nil || mergedFaceit != nil {
            let updated = PlayerOverviewStats(
                steamStats: mergedSteam,
                faceitStats: mergedFaceit,
                lastUpdated: .now
            )
            overviewStats = updated
            saveCachedStats(updated)
        }

        isLoading = false
        isRefreshing = false
    }

    public func clearStatsCache() {
        if let steamID = overviewStats?.steamStats?.steamID64 {
            snapshotStore.clearSnapshots(for: steamID)
        }
        UserDefaults.standard.removeObject(forKey: cacheKey)
        overviewStats = nil
        steamErrorMessage = nil
        faceitErrorMessage = nil
        hasCompletedInitialAttempt = false
        DebugLogger.shared.log("[StatsViewModel] Local stats cache and snapshots cleared.")
    }

    // MARK: - Internal Fetching

    private func fetchSteamSafely(steamID64: String, apiKey: String) async -> SteamPlayerStats? {
        guard !steamID64.isEmpty, !apiKey.isEmpty else {
            steamErrorMessage = SteamStatsError.missingCredentials.localizedDescription
            return nil
        }

        do {
            return try await steamService.fetchPlayerStats(steamID64: steamID64, apiKey: apiKey)
        } catch {
            steamErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func fetchFaceitSafely(
        identifier: String,
        fallbackSteamID64: String,
        apiKey: String
    ) async -> FaceitPlayerStats? {
        guard !apiKey.isEmpty else {
            if !identifier.isEmpty {
                faceitErrorMessage = FaceitStatsError.missingAPIKey.localizedDescription
            }
            return nil
        }

        guard !identifier.isEmpty || !fallbackSteamID64.isEmpty else {
            faceitErrorMessage = FaceitStatsError.missingPlayerIdentifier.localizedDescription
            return nil
        }

        do {
            let stats = try await faceitService.fetchPlayerStats(
                identifier: identifier,
                fallbackSteamID64: fallbackSteamID64,
                apiKey: apiKey
            )
            if AppCredentialsStore.readFaceitIdentifier().isEmpty {
                AppCredentialsStore.saveFaceitIdentifier(stats.nickname)
            }
            return stats
        } catch {
            faceitErrorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Local Cache Persistence

    private func loadCachedStats() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            let cached = try JSONDecoder().decode(PlayerOverviewStats.self, from: data)
            self.overviewStats = cached
            if let steam = cached.steamStats {
                snapshotStore.recordSnapshot(
                    steamID64: steam.steamID64,
                    rawStats: steam.rawCounters,
                    timestamp: steam.fetchedAt
                )
            }
            DebugLogger.shared.log("[StatsViewModel] Loaded cached player stats from \(cached.lastUpdated.formatted()).")
        } catch {
            DebugLogger.shared.log("[StatsViewModel] Failed to decode cached stats: \(error.localizedDescription)")
        }
    }

    private func saveCachedStats(_ stats: PlayerOverviewStats) {
        do {
            let data = try JSONEncoder().encode(stats)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            DebugLogger.shared.log("[StatsViewModel] Failed to encode stats cache: \(error.localizedDescription)")
        }
    }
}