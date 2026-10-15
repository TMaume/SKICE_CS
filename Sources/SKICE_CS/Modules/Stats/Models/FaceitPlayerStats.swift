import Foundation

// MARK: - FACEIT Open API v4 Raw Response Models

public struct FaceitPlayerSearchResponse: Codable, Sendable {
    public let items: [FaceitPlayerSearchItem]?
}

public struct FaceitPlayerSearchItem: Codable, Sendable {
    public let player_id: String
    public let nickname: String
}

public struct FaceitPlayerProfileResponse: Codable, Sendable {
    public let player_id: String
    public let nickname: String
    public let avatar: String?
    public let country: String?
    public let games: [String: FaceitGameDetails]?
}

public struct FaceitGameDetails: Codable, Sendable {
    public let region: String?
    public let game_player_id: String?
    public let skill_level: Int?
    public let faceit_elo: Int?
    public let game_player_name: String?
}

public struct FaceitPlayerStatsResponse: Codable, Sendable {
    public let player_id: String?
    public let game_id: String?
    public let lifetime: FaceitLifetimeStats?
}

public struct FaceitLifetimeStats: Codable, Sendable {
    public let matches: String?
    public let wins: String?
    public let winRatePercentage: String?
    public let averageKDRatio: String?
    public let averageHeadshotsPercentage: String?
    public let adr: String?
    public let currentWinStreak: String?
    public let longestWinStreak: String?
    public let recentResults: [String?]?

    enum CodingKeys: String, CodingKey {
        case matches = "Matches"
        case wins = "Wins"
        case winRatePercentage = "Win Rate %"
        case averageKDRatio = "Average K/D Ratio"
        case averageHeadshotsPercentage = "Average Headshots %"
        case adr = "ADR"
        case currentWinStreak = "Current Win Streak"
        case longestWinStreak = "Longest Win Streak"
        case recentResults = "Recent Results"
    }
}

public struct FaceitRankingResponse: Codable, Sendable {
    public let position: Int?
}

public struct FaceitMatchHistoryResponse: Codable, Sendable {
    public let items: [FaceitMatchHistoryItem]?
}

public struct FaceitMatchHistoryItem: Codable, Sendable {
    public let match_id: String
    public let game_id: String?
    public let region: String?
    public let competition_name: String?
    public let competition_type: String?
    public let game_mode: String?
    public let started_at: Int?
    public let finished_at: Int?
    public let results: FaceitMatchResults?
    public let teams: [String: FaceitMatchFaction]?
}

public struct FaceitMatchResults: Codable, Sendable {
    public let winner: String?
    public let score: [String: Int]?
}

public struct FaceitMatchFaction: Codable, Sendable {
    public let team_id: String?
    public let nickname: String?
    public let players: [FaceitMatchPlayer]?
}

public struct FaceitMatchPlayer: Codable, Sendable {
    public let player_id: String?
    public let nickname: String?
}

// MARK: - FACEIT Per-Match Stats Endpoint (/matches/{match_id}/stats)

public struct FaceitMatchStatsResponse: Codable, Sendable {
    public let rounds: [FaceitMatchRoundStats]?
}

public struct FaceitMatchRoundStats: Codable, Sendable {
    public let game_mode: String?
    public let round_stats: FaceitRoundMetadata?
    public let teams: [FaceitMatchTeamStats]?
}

public struct FaceitRoundMetadata: Codable, Sendable {
    public let map: String?
    public let score: String?
    public let rounds: String?

    enum CodingKeys: String, CodingKey {
        case map = "Map"
        case score = "Score"
        case rounds = "Rounds"
    }
}

public struct FaceitMatchTeamStats: Codable, Sendable {
    public let team_id: String?
    public let players: [FaceitMatchPlayerScoreboard]?
}

public struct FaceitMatchPlayerScoreboard: Codable, Sendable {
    public let player_id: String?
    public let nickname: String?
    public let player_stats: [String: String]?
}

// MARK: - Domain Model: FaceitMatchSummary

public struct FaceitMatchSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let competitionName: String
    public let gameMode: String
    public let mapCode: String?
    public let mapDisplayName: String
    public let finishedAt: Date
    public let isWin: Bool
    public let playerTeamScore: Int
    public let opponentTeamScore: Int
    public let opponentTeamName: String
    public let kills: Int?
    public let deaths: Int?
    public let mvps: Int?
    public let kdRatio: Double?
    public let headshotsPercentage: Double?
    public let adr: Double?

    public var scoreDisplay: String {
        "\(playerTeamScore) - \(opponentTeamScore)"
    }

    public var hasDetailedScoreboard: Bool {
        kills != nil && deaths != nil
    }
}

// MARK: - Domain Model: FaceitPlayerStats

public struct FaceitPlayerStats: Codable, Equatable, Sendable {
    public let playerId: String
    public let nickname: String
    public let avatarURL: String?
    public let country: String
    public let region: String
    public let elo: Int
    public let skillLevel: Int
    public let regionalRank: Int?
    public let totalMatches: Int
    public let totalWins: Int
    public let winRatePercentage: Double
    public let averageKDRatio: Double
    public let averageHeadshotsPercentage: Double
    public let adr: Double?
    public let currentWinStreak: Int
    public let longestWinStreak: Int
    public let recentResults: [Bool]
    public let recentMatches: [FaceitMatchSummary]
    public let fetchedAt: Date

    public init(
        profile: FaceitPlayerProfileResponse,
        statsResponse: FaceitPlayerStatsResponse?,
        historyResponse: FaceitMatchHistoryResponse?,
        matchDetailsById: [String: FaceitMatchStatsResponse] = [:],
        regionalRank: Int?,
        fetchedAt: Date = .now
    ) {
        let cs2Details = profile.games?["cs2"] ?? profile.games?["csgo"]
        let lifetime = statsResponse?.lifetime

        self.playerId = profile.player_id
        self.nickname = profile.nickname
        self.avatarURL = profile.avatar
        self.country = (profile.country ?? "UN").uppercased()
        self.region = cs2Details?.region ?? "EU"
        self.elo = cs2Details?.faceit_elo ?? 1000
        self.skillLevel = min(max(cs2Details?.skill_level ?? 1, 1), 10)
        self.regionalRank = regionalRank

        self.totalMatches = Self.parseInt(lifetime?.matches)
        self.totalWins = Self.parseInt(lifetime?.wins)
        self.winRatePercentage = Self.parseDouble(lifetime?.winRatePercentage)
        self.averageKDRatio = Self.parseDouble(lifetime?.averageKDRatio)
        self.averageHeadshotsPercentage = Self.parseDouble(lifetime?.averageHeadshotsPercentage)

        let rawAdr = Self.parseDouble(lifetime?.adr)
        self.adr = rawAdr > 0 ? min(rawAdr, 200.0) : nil

        self.currentWinStreak = Self.parseInt(lifetime?.currentWinStreak)
        self.longestWinStreak = Self.parseInt(lifetime?.longestWinStreak)

        let parsedRecent = (lifetime?.recentResults ?? []).compactMap { val -> Bool? in
            guard let val else { return nil }
            return val == "1"
        }

        let targetPlayerId = profile.player_id
        let parsedHistory: [FaceitMatchSummary] = (historyResponse?.items ?? []).compactMap { item in
            let factions = item.teams ?? [:]
            var userFactionKey: String?
            var opponentFactionKey: String?

            for (key, faction) in factions {
                let containsPlayer = (faction.players ?? []).contains {
                    $0.player_id == targetPlayerId
                }
                if containsPlayer {
                    userFactionKey = key
                } else {
                    opponentFactionKey = key
                }
            }

            let resolvedUserKey = userFactionKey ?? "faction1"
            let resolvedOpponentKey = opponentFactionKey ?? (resolvedUserKey == "faction1" ? "faction2" : "faction1")

            let winnerKey = item.results?.winner ?? ""
            let isWin = winnerKey == resolvedUserKey
            var userScore = item.results?.score?[resolvedUserKey] ?? 0
            var oppScore = item.results?.score?[resolvedOpponentKey] ?? 0
            let oppName = factions[resolvedOpponentKey]?.nickname ?? "Opponent"
            let timestamp = TimeInterval(item.finished_at ?? item.started_at ?? Int(Date().timeIntervalSince1970))

            // Extract granular scoreboard & map telemetry if available
            let roundDetail = matchDetailsById[item.match_id]?.rounds?.first
            let rawMapCode = roundDetail?.round_stats?.map
            let cleanMapName = rawMapCode.map { SteamMapCatalog.cleanDisplayName(from: $0) } ?? "CS2 5v5"

            // Parse real round scores from "13 / 8" if history header only returned 1 / 0 series score
            if (userScore <= 1 && oppScore <= 1),
               let scoreString = roundDetail?.round_stats?.score {
                let parts = scoreString
                    .Split(whereSeparator: { $0 == "/" || $0 == "-" })
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 2, let maxPart = parts.max(), let minPart = parts.min() {
                    userScore = isWin ? maxPart : minPart
                    oppScore = isWin ? minPart : maxPart
                }
            }

            let playerEntry = roundDetail?.teams?
                .flatMap { $0.players ?? [] }
                .first(where: { $0.player_id == targetPlayerId })

            let statsDict = playerEntry?.player_stats ?? [:]
            let matchKills = statsDict["Kills"].flatMap { Int($0) }
            let matchDeaths = statsDict["Deaths"].flatMap { Int($0) }
            let matchMVPs = statsDict["MVPs"].flatMap { Int($0) }
            let matchKD = statsDict["K/D Ratio"].flatMap { Self.parseOptionalDouble($0) }
                ?? (matchKills != nil && matchDeaths != nil ? Double(matchKills!) / Double(max(matchDeaths!, 1)) : nil)
            let matchHS = statsDict["Headshots %"].flatMap { Self.parseOptionalDouble($0) }
            let matchADR = statsDict["ADR"].flatMap { Self.parseOptionalDouble($0) }

            let modeLabel = roundDetail?.game_mode ?? item.game_mode ?? "5v5 Queue"

            return FaceitMatchSummary(
                id: item.match_id,
                competitionName: item.competition_name ?? "FACEIT CS2",
                gameMode: modeLabel,
                mapCode: rawMapCode,
                mapDisplayName: cleanMapName,
                finishedAt: Date(timeIntervalSince1970: timestamp),
                isWin: isWin,
                playerTeamScore: userScore,
                opponentTeamScore: oppScore,
                opponentTeamName: oppName,
                kills: matchKills,
                deaths: matchDeaths,
                mvps: matchMVPs,
                kdRatio: matchKD,
                headshotsPercentage: matchHS,
                adr: matchADR
            )
        }

        self.recentMatches = parsedHistory
        if !parsedRecent.isEmpty {
            self.recentResults = parsedRecent
        } else {
            self.recentResults = parsedHistory.prefix(5).map(\.isWin)
        }
        self.fetchedAt = fetchedAt
    }

    // MARK: - Timeframe Filtering

    public func matches(in interval: DateInterval?) -> [FaceitMatchSummary] {
        guard let interval else { return recentMatches }
        return recentMatches.filter { interval.contains($0.finishedAt) }
    }

    // MARK: - FACEIT CS2 ELO Tier Thresholds

    private static let levelThresholds: [(level: Int, min: Int, max: Int?)] = [
        (1, 100, 500),
        (2, 501, 750),
        (3, 751, 900),
        (4, 901, 1050),
        (5, 1051, 1200),
        (6, 1201, 1350),
        (7, 1351, 1530),
        (8, 1531, 1750),
        (9, 1751, 2000),
        (10, 2001, nil)
    ]

    public var currentLevelFloorElo: Int {
        Self.levelThresholds.first(where: { $0.level == skillLevel })?.min ?? 100
    }

    public var nextLevelTargetElo: Int? {
        guard let ceiling = Self.levelThresholds.first(where: { $0.level == skillLevel })?.max else {
            return nil
        }
        return ceiling + 1
    }

    public var eloNeededForNextLevel: Int? {
        guard let target = nextLevelTargetElo else { return nil }
        return max(target - elo, 0)
    }

    public var levelProgress: Double {
        guard let target = nextLevelTargetElo else { return 1.0 }
        let span = Double(max(target - currentLevelFloorElo, 1))
        let earned = Double(max(elo - currentLevelFloorElo, 0))
        return min(max(earned / span, 0.0), 1.0)
    }

    // MARK: - Parsing Helpers

    private static func parseInt(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        let cleaned = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(cleaned) ?? Int(Double(cleaned) ?? 0)
    }

    private static func parseDouble(_ raw: String?) -> Double {
        parseOptionalDouble(raw) ?? 0.0
    }

    private static func parseOptionalDouble(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }
}

private extension String {
    func Split(whereSeparator isSeparator: (Character) -> Bool) -> [Substring] {
        self.split(whereSeparator: isSeparator)
    }
}