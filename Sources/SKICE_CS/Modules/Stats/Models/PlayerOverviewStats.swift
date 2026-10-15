import Foundation

public enum StatsPlatformFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case combined = "Overview"
    case steam = "Steam"
    case faceit = "FACEIT"

    public var id: String { rawValue }
}

public enum StatsTimeFrame: String, CaseIterable, Codable, Identifiable, Sendable {
    case allTime = "All-Time"
    case hours24 = "24 Hours"
    case days7 = "7 Days"
    case days30 = "30 Days"
    case custom = "Custom"

    public var id: String { rawValue }

    public func dateInterval(customStart: Date, customEnd: Date, now: Date = .now) -> DateInterval {
        switch self {
        case .allTime:
            return DateInterval(start: .distantPast, end: now)
        case .hours24:
            return DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        case .days7:
            return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .days30:
            return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case .custom:
            let orderedStart = min(customStart, customEnd)
            let orderedEnd = max(customStart, customEnd)
            return DateInterval(start: orderedStart, end: orderedEnd)
        }
    }
}

public struct PlayerOverviewStats: Codable, Equatable, Sendable {
    public let steamStats: SteamPlayerStats?
    public let faceitStats: FaceitPlayerStats?
    public let lastUpdated: Date

    public init(
        steamStats: SteamPlayerStats?,
        faceitStats: FaceitPlayerStats?,
        lastUpdated: Date = .now
    ) {
        self.steamStats = steamStats
        self.faceitStats = faceitStats
        self.lastUpdated = lastUpdated
    }

    public var hasAnyData: Bool {
        steamStats != nil || faceitStats != nil
    }

    // MARK: - Unified Metric Accessors (Strict Platform Isolation)

    public func kdRatio(
        for filter: StatsPlatformFilter,
        activeSteam: SteamPlayerStats?
    ) -> Double {
        let targetSteam = activeSteam ?? steamStats
        switch filter {
        case .steam:
            return targetSteam?.kdRatio ?? 0.0
        case .faceit:
            return faceitStats?.averageKDRatio ?? 0.0
        case .combined:
            if let steam = targetSteam, steam.totalKills > 0 {
                return steam.kdRatio
            }
            return faceitStats?.averageKDRatio ?? 0.0
        }
    }

    public func winRatePercentage(
        for filter: StatsPlatformFilter,
        faction: StatsFactionFilter = .both,
        activeSteam: SteamPlayerStats?,
        filteredFaceitMatches: [FaceitMatchSummary]?
    ) -> Double {
        let targetSteam = activeSteam ?? steamStats
        let faceitWinRate: Double = {
            if let matches = filteredFaceitMatches, !matches.isEmpty {
                let wins = matches.filter(\.isWin).count
                return (Double(wins) / Double(matches.count)) * 100.0
            }
            return faceitStats?.winRatePercentage ?? 0.0
        }()

        switch filter {
        case .steam:
            guard let targetSteam else { return 0.0 }
            return faction == .both
                ? targetSteam.winRatePercentage
                : targetSteam.factionSummary(for: faction).dominancePercentage
        case .faceit:
            return faceitWinRate
        case .combined:
            if faction != .both, let targetSteam {
                return targetSteam.factionSummary(for: faction).dominancePercentage
            }
            if let targetSteam, targetSteam.matchesPlayed > 0 || targetSteam.roundsPlayed > 0 {
                return targetSteam.winRatePercentage
            }
            return faceitWinRate
        }
    }

    public func headshotPercentage(
        for filter: StatsPlatformFilter,
        activeSteam: SteamPlayerStats?
    ) -> Double {
        let targetSteam = activeSteam ?? steamStats
        switch filter {
        case .steam:
            return targetSteam?.headshotPercentage ?? 0.0
        case .faceit:
            return faceitStats?.averageHeadshotsPercentage ?? 0.0
        case .combined:
            if let steam = targetSteam, steam.totalKills > 0 {
                return steam.headshotPercentage
            }
            return faceitStats?.averageHeadshotsPercentage ?? 0.0
        }
    }

    public func totalMatches(
        for filter: StatsPlatformFilter,
        activeSteam: SteamPlayerStats?,
        filteredFaceitMatches: [FaceitMatchSummary]?
    ) -> Int {
        let targetSteam = activeSteam ?? steamStats
        let faceitCount = filteredFaceitMatches?.count ?? (faceitStats?.totalMatches ?? 0)
        switch filter {
        case .steam:
            return targetSteam?.matchesPlayed ?? 0
        case .faceit:
            return faceitCount
        case .combined:
            return (targetSteam?.matchesPlayed ?? 0) + faceitCount
        }
    }
}