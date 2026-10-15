import Foundation

// MARK: - Steam Web API Raw Response Models (ISteamUserStats/GetUserStatsForGame/v0002)

public struct SteamUserStatsResponse: Codable, Sendable {
    public let playerstats: SteamPlayerStatsPayload?
}

public struct SteamPlayerStatsPayload: Codable, Sendable {
    public let steamID: String?
    public let gameName: String?
    public let stats: [SteamRawStat]?
}

public struct SteamRawStat: Codable, Sendable {
    public let name: String
    public let value: Double

    public var intValue: Int {
        Int(value.rounded())
    }

    enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        if let intVal = try? container.decode(Int.self, forKey: .value) {
            self.value = Double(intVal)
        } else {
            self.value = try container.decode(Double.self, forKey: .value)
        }
    }
}

// MARK: - Faction / Team Filter

public enum StatsFactionFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case both = "Both"
    case terrorist = "T"
    case counterTerrorist = "CT"

    public var id: String { rawValue }

    public var fullDisplayName: String {
        switch self {
        case .both:
            return "Combined Factions"
        case .terrorist:
            return "Terrorist (T-Side)"
        case .counterTerrorist:
            return "Counter-Terrorist (CT-Side)"
        }
    }
}

public enum WeaponFactionAffinity: String, Codable, Sendable {
    case terrorist = "T"
    case counterTerrorist = "CT"
    case shared = "Shared"

    public func matches(_ filter: StatsFactionFilter) -> Bool {
        switch filter {
        case .both:
            return true
        case .terrorist:
            return self == .terrorist || self == .shared
        case .counterTerrorist:
            return self == .counterTerrorist || self == .shared
        }
    }

    public func isExclusive(to filter: StatsFactionFilter) -> Bool {
        switch filter {
        case .both:
            return true
        case .terrorist:
            return self == .terrorist
        case .counterTerrorist:
            return self == .counterTerrorist
        }
    }
}

// MARK: - Weapon Category & Catalog

public enum WeaponCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case all = "All"
    case rifles = "Rifles"
    case pistols = "Pistols"
    case smgs = "SMGs"
    case heavy = "Heavy"
    case snipers = "Snipers"

    public var id: String { rawValue }
}

public struct WeaponDescriptor: Sendable {
    public let key: String
    public let displayName: String
    public let category: WeaponCategory
    public let faction: WeaponFactionAffinity
    public let hsAffinityFactor: Double
}

public enum SteamWeaponCatalog {
    public static let allWeapons: [WeaponDescriptor] = [
        // Rifles
        WeaponDescriptor(key: "ak47", displayName: "AK-47", category: .rifles, faction: .terrorist, hsAffinityFactor: 1.18),
        WeaponDescriptor(key: "m4a1", displayName: "M4A4 / M4A1-S", category: .rifles, faction: .counterTerrorist, hsAffinityFactor: 0.96),
        WeaponDescriptor(key: "galilar", displayName: "Galil AR", category: .rifles, faction: .terrorist, hsAffinityFactor: 0.92),
        WeaponDescriptor(key: "famas", displayName: "FAMAS", category: .rifles, faction: .counterTerrorist, hsAffinityFactor: 0.90),
        WeaponDescriptor(key: "aug", displayName: "AUG", category: .rifles, faction: .counterTerrorist, hsAffinityFactor: 0.88),
        WeaponDescriptor(key: "sg556", displayName: "SG 553", category: .rifles, faction: .terrorist, hsAffinityFactor: 1.12),

        // Snipers
        WeaponDescriptor(key: "awp", displayName: "AWP", category: .snipers, faction: .shared, hsAffinityFactor: 0.34),
        WeaponDescriptor(key: "ssg08", displayName: "SSG 08", category: .snipers, faction: .shared, hsAffinityFactor: 1.25),
        WeaponDescriptor(key: "scar20", displayName: "SCAR-20", category: .snipers, faction: .counterTerrorist, hsAffinityFactor: 0.65),
        WeaponDescriptor(key: "g3sg1", displayName: "G3SG1", category: .snipers, faction: .terrorist, hsAffinityFactor: 0.65),

        // Pistols
        WeaponDescriptor(key: "deagle", displayName: "Desert Eagle", category: .pistols, faction: .shared, hsAffinityFactor: 1.38),
        WeaponDescriptor(key: "hkp2000", displayName: "USP-S / P2000", category: .pistols, faction: .counterTerrorist, hsAffinityFactor: 1.28),
        WeaponDescriptor(key: "glock", displayName: "Glock-18", category: .pistols, faction: .terrorist, hsAffinityFactor: 1.15),
        WeaponDescriptor(key: "p250", displayName: "P250", category: .pistols, faction: .shared, hsAffinityFactor: 1.10),
        WeaponDescriptor(key: "fiveseven", displayName: "Five-SeveN", category: .pistols, faction: .counterTerrorist, hsAffinityFactor: 1.12),
        WeaponDescriptor(key: "tec9", displayName: "Tec-9", category: .pistols, faction: .terrorist, hsAffinityFactor: 1.08),
        WeaponDescriptor(key: "elite", displayName: "Dual Berettas", category: .pistols, faction: .shared, hsAffinityFactor: 0.85),

        // SMGs
        WeaponDescriptor(key: "mp9", displayName: "MP9", category: .smgs, faction: .counterTerrorist, hsAffinityFactor: 0.82),
        WeaponDescriptor(key: "mac10", displayName: "MAC-10", category: .smgs, faction: .terrorist, hsAffinityFactor: 0.80),
        WeaponDescriptor(key: "mp7", displayName: "MP7 / MP5-SD", category: .smgs, faction: .shared, hsAffinityFactor: 0.84),
        WeaponDescriptor(key: "ump45", displayName: "UMP-45", category: .smgs, faction: .shared, hsAffinityFactor: 0.82),
        WeaponDescriptor(key: "p90", displayName: "P90", category: .smgs, faction: .shared, hsAffinityFactor: 0.74),
        WeaponDescriptor(key: "bizon", displayName: "PP-Bizon", category: .smgs, faction: .shared, hsAffinityFactor: 0.72),

        // Heavy
        WeaponDescriptor(key: "xm1014", displayName: "XM1014", category: .heavy, faction: .shared, hsAffinityFactor: 0.55),
        WeaponDescriptor(key: "mag7", displayName: "MAG-7", category: .heavy, faction: .counterTerrorist, hsAffinityFactor: 0.52),
        WeaponDescriptor(key: "nova", displayName: "Nova", category: .heavy, faction: .shared, hsAffinityFactor: 0.58),
        WeaponDescriptor(key: "sawedoff", displayName: "Sawed-Off", category: .heavy, faction: .terrorist, hsAffinityFactor: 0.50),
        WeaponDescriptor(key: "negev", displayName: "Negev", category: .heavy, faction: .shared, hsAffinityFactor: 0.68),
        WeaponDescriptor(key: "m249", displayName: "M249", category: .heavy, faction: .shared, hsAffinityFactor: 0.70)
    ]
}

// MARK: - Map Catalog & Performance Model

public struct MapDescriptor: Sendable {
    public let mapCode: String
    public let displayName: String
    public let isActiveDuty: Bool
    public let iconName: String
    public let tacticalProfile: String
}

public enum SteamMapCatalog {
    public static let allMaps: [MapDescriptor] = [
        MapDescriptor(
            mapCode: "de_mirage",
            displayName: "Mirage",
            isActiveDuty: true,
            iconName: "sun.max.fill",
            tacticalProfile: "Active Duty • Four-square mid-control & connector split defusal map"
        ),
        MapDescriptor(
            mapCode: "de_inferno",
            displayName: "Inferno",
            isActiveDuty: true,
            iconName: "flame.fill",
            tacticalProfile: "Active Duty • Utility-focused banana control & tight site retakes"
        ),
        MapDescriptor(
            mapCode: "de_nuke",
            displayName: "Nuke",
            isActiveDuty: true,
            iconName: "atom",
            tacticalProfile: "Active Duty • Vertical dual-deck bombsites & fast vent rotations"
        ),
        MapDescriptor(
            mapCode: "de_dust2",
            displayName: "Dust II",
            isActiveDuty: true,
            iconName: "wind",
            tacticalProfile: "Active Duty • Classic three-lane layout with long-range sniper duels"
        ),
        MapDescriptor(
            mapCode: "de_ancient",
            displayName: "Ancient",
            isActiveDuty: true,
            iconName: "leaf.fill",
            tacticalProfile: "Active Duty • Temple mid/donut control & heavy B-lane pressure"
        ),
        MapDescriptor(
            mapCode: "de_anubis",
            displayName: "Anubis",
            isActiveDuty: true,
            iconName: "pyramid.fill",
            tacticalProfile: "Active Duty • Canal water control & multi-angle mid-to-site splits"
        ),
        MapDescriptor(
            mapCode: "de_vertigo",
            displayName: "Vertigo",
            isActiveDuty: true,
            iconName: "building.2.fill",
            tacticalProfile: "Active Duty • High-elevation skyscraper combat & A-ramp executes"
        ),
        MapDescriptor(
            mapCode: "de_overpass",
            displayName: "Overpass",
            isActiveDuty: false,
            iconName: "road.lanes",
            tacticalProfile: "Reserve Pool • Long rotational pathways & connector control"
        ),
        MapDescriptor(
            mapCode: "de_train",
            displayName: "Train",
            isActiveDuty: false,
            iconName: "tram.fill",
            tacticalProfile: "Reserve Pool • Railyard sightlines & tight ladder/train angles"
        ),
        MapDescriptor(
            mapCode: "de_cbble",
            displayName: "Cobblestone",
            isActiveDuty: false,
            iconName: "shield.lefthalf.filled",
            tacticalProfile: "Reserve Pool • Expansive B-plateau & close-quarters drop-room entry"
        ),
        MapDescriptor(
            mapCode: "cs_office",
            displayName: "Office",
            isActiveDuty: false,
            iconName: "building.columns.fill",
            tacticalProfile: "Hostage Pool • Close-quarters indoor corridors & chokepoints"
        ),
        MapDescriptor(
            mapCode: "cs_italy",
            displayName: "Italy",
            isActiveDuty: false,
            iconName: "wineglass.fill",
            tacticalProfile: "Hostage Pool • Split market/tunnel lanes & long apartment halls"
        )
    ]

    public static func cleanDisplayName(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let known = allMaps.first(where: { $0.mapCode.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return known.displayName
        }
        let stripped = trimmed
            .replacingOccurrences(of: "^(de_|cs_|ar_|gd_)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch stripped.lowercased() {
        case "dust2":
            return "Dust II"
        case "cbble":
            return "Cobblestone"
        default:
            return stripped.isEmpty ? "Unknown Map" : stripped.capitalized
        }
    }

    public static func descriptor(for mapCode: String) -> MapDescriptor {
        if let match = allMaps.first(where: { $0.mapCode.caseInsensitiveCompare(mapCode) == .orderedSame }) {
            return match
        }
        return MapDescriptor(
            mapCode: mapCode,
            displayName: cleanDisplayName(from: mapCode),
            isActiveDuty: false,
            iconName: "map.fill",
            tacticalProfile: "Counter-Strike competitive map"
        )
    }
}

public enum MapVictoryStatus: String, Codable, Equatable, Sendable {
    case dominant = "DOMINANT"
    case positive = "POSITIVE WIN RATE"
    case balanced = "CONTESTED"
    case challenging = "BELOW 50%"
    case unplayed = "NO ROUNDS RECORDED"
}

public struct SteamMapStatSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let mapCode: String
    public let displayName: String
    public let isActiveDuty: Bool
    public let iconName: String
    public let tacticalProfile: String
    public let roundsPlayed: Int
    public let roundsWon: Int
    public let roundsLost: Int
    public let winRatePercentage: Double
    public let victoryStatus: MapVictoryStatus
    public let terroristRoundsWon: Int?
    public let terroristRoundsPlayed: Int?
    public let counterTerroristRoundsWon: Int?
    public let counterTerroristRoundsPlayed: Int?

    public var terroristWinRatePercentage: Double? {
        guard let won = terroristRoundsWon, let played = terroristRoundsPlayed, played > 0 else {
            return nil
        }
        return min((Double(won) / Double(played)) * 100.0, 100.0)
    }

    public var counterTerroristWinRatePercentage: Double? {
        guard let won = counterTerroristRoundsWon, let played = counterTerroristRoundsPlayed, played > 0 else {
            return nil
        }
        return min((Double(won) / Double(played)) * 100.0, 100.0)
    }

    public var hasSideBreakdownInSchema: Bool {
        terroristWinRatePercentage != nil || counterTerroristWinRatePercentage != nil ||
        (terroristRoundsWon != nil && counterTerroristRoundsWon != nil)
    }

    public init(
        descriptor: MapDescriptor,
        roundsPlayed: Int,
        roundsWon: Int,
        terroristRoundsWon: Int? = nil,
        terroristRoundsPlayed: Int? = nil,
        counterTerroristRoundsWon: Int? = nil,
        counterTerroristRoundsPlayed: Int? = nil
    ) {
        let safePlayed = max(roundsPlayed, 0)
        let clampedWon = min(max(roundsWon, 0), safePlayed)
        let winRate = safePlayed > 0 ? (Double(clampedWon) / Double(safePlayed)) * 100.0 : 0.0

        self.id = descriptor.mapCode
        self.mapCode = descriptor.mapCode
        self.displayName = descriptor.displayName
        self.isActiveDuty = descriptor.isActiveDuty
        self.iconName = descriptor.iconName
        self.tacticalProfile = descriptor.tacticalProfile
        self.roundsPlayed = safePlayed
        self.roundsWon = clampedWon
        self.roundsLost = max(safePlayed - clampedWon, 0)
        self.winRatePercentage = winRate
        self.terroristRoundsWon = terroristRoundsWon
        self.terroristRoundsPlayed = terroristRoundsPlayed
        self.counterTerroristRoundsWon = counterTerroristRoundsWon
        self.counterTerroristRoundsPlayed = counterTerroristRoundsPlayed

        if safePlayed == 0 {
            self.victoryStatus = .unplayed
        } else if winRate >= 55.0 {
            self.victoryStatus = .dominant
        } else if winRate >= 50.0 {
            self.victoryStatus = .positive
        } else if winRate >= 47.0 {
            self.victoryStatus = .balanced
        } else {
            self.victoryStatus = .challenging
        }
    }
}

// MARK: - Weapon Stat Summary

public struct SteamWeaponStatSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let category: WeaponCategory
    public let faction: WeaponFactionAffinity
    public let kills: Int
    public let shotsFired: Int
    public let shotsHit: Int
    public let headshotPercentage: Double

    public var accuracyPercentage: Double {
        guard shotsFired > 0 else { return 0.0 }
        return min((Double(shotsHit) / Double(shotsFired)) * 100.0, 100.0)
    }
}

// MARK: - Faction Breakdown Summary

public struct FactionPerformanceSummary: Codable, Equatable, Sendable {
    public let faction: StatsFactionFilter
    public let hasDirectRoundWinsInSchema: Bool
    public let terroristRoundsWon: Int
    public let counterTerroristRoundsWon: Int
    public let selectedSideRoundsWon: Int
    public let dominancePercentage: Double
    public let terroristDominancePercentage: Double
    public let counterTerroristDominancePercentage: Double
    public let factionWeaponKills: Int
    public let factionShotsFired: Int
    public let factionShotsHit: Int
    public let factionAccuracyPercentage: Double
    public let objectiveCount: Int
    public let objectiveTitle: String
    public let objectiveEfficiencyPercent: Double
    public let objectiveEfficiencySubtitle: String
}

// MARK: - Domain Model: SteamPlayerStats (Lifetime Career Totals)

public struct SteamPlayerStats: Codable, Equatable, Sendable {
    public let steamID64: String
    public let totalKills: Int
    public let totalDeaths: Int
    public let kdRatio: Double
    public let headshotKills: Int
    public let headshotPercentage: Double
    public let mvpCount: Int
    public let matchesPlayed: Int
    public let matchesWon: Int
    public let roundsPlayed: Int
    public let roundsWon: Int
    public let winRatePercentage: Double
    public let timePlayedSeconds: Int
    public let timePlayedHours: Double
    public let totalDamageDone: Int
    public let shotsFired: Int
    public let shotsHit: Int
    public let accuracyPercentage: Double
    public let bombsPlanted: Int
    public let bombsDefused: Int
    public let explicitTerroristWins: Int?
    public let explicitCounterTerroristWins: Int?
    public let allWeapons: [SteamWeaponStatSummary]
    public let topWeapons: [SteamWeaponStatSummary]
    public let mapStats: [SteamMapStatSummary]
    public let rawCounters: [String: Int]
    public let fetchedAt: Date

    public init(
        steamID64: String,
        payload: SteamPlayerStatsPayload,
        fetchedAt: Date = .now
    ) {
        var map: [String: Int] = [:]
        if let rawStats = payload.stats {
            map.reserveCapacity(rawStats.count)
            for stat in rawStats {
                map[stat.name] = stat.intValue
            }
        }
        self.init(
            steamID64: steamID64,
            rawCounters: map,
            fetchedAt: fetchedAt
        )
    }

    public init(
        steamID64: String,
        rawCounters map: [String: Int],
        fetchedAt: Date = .now
    ) {
        let kills = map["total_kills"] ?? 0
        let deaths = map["total_deaths"] ?? 0
        let hsKills = map["total_kills_headshot"] ?? 0
        let mvps = map["total_mvps"] ?? 0
        let mPlayed = map["total_matches_played"] ?? 0
        let mWon = map["total_matches_won"] ?? 0
        let rPlayed = map["total_rounds_played"] ?? 0
        let rWon = map["total_wins"] ?? 0
        let timeSec = map["total_time_played"] ?? 0
        let dmg = map["total_damage_done"] ?? 0
        let fired = map["total_shots_fired"] ?? 0
        let hit = map["total_shots_hit"] ?? 0

        self.steamID64 = steamID64
        self.rawCounters = map
        self.totalKills = kills
        self.totalDeaths = deaths
        self.kdRatio = Double(kills) / Double(max(deaths, 1))
        self.headshotKills = hsKills
        let globalHS = kills > 0 ? min((Double(hsKills) / Double(kills)) * 100.0, 100.0) : 0.0
        self.headshotPercentage = globalHS
        self.mvpCount = mvps
        self.matchesPlayed = mPlayed
        self.matchesWon = mWon
        self.roundsPlayed = rPlayed
        self.roundsWon = rWon

        // Win Rate %: Total Matches Won / Total Matches Played (with round win rate fallback if match counters are 0)
        if mPlayed > 0, mWon <= mPlayed {
            self.winRatePercentage = min((Double(mWon) / Double(mPlayed)) * 100.0, 100.0)
        } else if rPlayed > 0 {
            self.winRatePercentage = min((Double(rWon) / Double(rPlayed)) * 100.0, 100.0)
        } else {
            self.winRatePercentage = 0.0
        }

        self.timePlayedSeconds = timeSec
        self.timePlayedHours = Double(timeSec) / 3600.0
        self.totalDamageDone = dmg
        self.shotsFired = fired
        self.shotsHit = hit
        self.accuracyPercentage = fired > 0 ? min((Double(hit) / Double(fired)) * 100.0, 100.0) : 0.0
        self.bombsPlanted = map["total_planted_bombs"] ?? 0
        self.bombsDefused = map["total_defused_bombs"] ?? 0

        let rawTWins = map["total_wins_terrorist"] ?? map["total_t_wins"]
        let rawCTWins = map["total_wins_counterterrorist"] ?? map["total_ct_wins"]
        self.explicitTerroristWins = rawTWins
        self.explicitCounterTerroristWins = rawCTWins

        // Parse Map Performance
        let computedMaps: [SteamMapStatSummary] = SteamMapCatalog.allMaps.compactMap { descriptor in
            let mapRounds = map["total_rounds_map_\(descriptor.mapCode)"] ?? 0
            let mapWins = map["total_wins_map_\(descriptor.mapCode)"] ?? 0
            guard mapRounds > 0 || descriptor.isActiveDuty else { return nil }

            let mapTWins = map["total_wins_map_\(descriptor.mapCode)_t"]
            let mapTRounds = map["total_rounds_map_\(descriptor.mapCode)_t"]
            let mapCTWins = map["total_wins_map_\(descriptor.mapCode)_ct"]
            let mapCTRounds = map["total_rounds_map_\(descriptor.mapCode)_ct"]

            return SteamMapStatSummary(
                descriptor: descriptor,
                roundsPlayed: mapRounds,
                roundsWon: mapWins,
                terroristRoundsWon: mapTWins,
                terroristRoundsPlayed: mapTRounds,
                counterTerroristRoundsWon: mapCTWins,
                counterTerroristRoundsPlayed: mapCTRounds
            )
        }
        .sorted { lhs, rhs in
            if lhs.roundsPlayed != rhs.roundsPlayed {
                return lhs.roundsPlayed > rhs.roundsPlayed
            }
            return lhs.displayName < rhs.displayName
        }

        let mapsWithPlaytime = computedMaps.filter { $0.roundsPlayed > 0 }
        self.mapStats = mapsWithPlaytime.isEmpty ? computedMaps : mapsWithPlaytime

        // Parse Full Weapon Mastery Catalog
        let parsedWeapons: [SteamWeaponStatSummary] = SteamWeaponCatalog.allWeapons.compactMap { descriptor in
            let wKills = map["total_kills_\(descriptor.key)"] ?? 0
            guard wKills > 0 else { return nil }
            let wFired = map["total_shots_\(descriptor.key)"] ?? 0
            let wHit = map["total_hits_\(descriptor.key)"] ?? 0
            let estimatedWeaponHS = min(max(globalHS * descriptor.hsAffinityFactor, 8.0), 92.0)

            return SteamWeaponStatSummary(
                id: descriptor.key,
                displayName: descriptor.displayName,
                category: descriptor.category,
                faction: descriptor.faction,
                kills: wKills,
                shotsFired: wFired,
                shotsHit: wHit,
                headshotPercentage: estimatedWeaponHS
            )
        }
        .sorted { $0.kills > $1.kills }

        self.allWeapons = parsedWeapons
        self.topWeapons = Array(parsedWeapons.prefix(3))
        self.fetchedAt = fetchedAt
    }

    // MARK: - Faction-Filtered Queries

    public func weapons(for faction: StatsFactionFilter) -> [SteamWeaponStatSummary] {
        switch faction {
        case .both:
            return allWeapons
        case .terrorist, .counterTerrorist:
            let exclusive = allWeapons.filter { $0.faction.isExclusive(to: faction) }
            return exclusive.isEmpty ? allWeapons.filter { $0.faction.matches(faction) } : exclusive
        }
    }

    public func factionSummary(for faction: StatsFactionFilter) -> FactionPerformanceSummary {
        let tExclusiveWeapons = allWeapons.filter { $0.faction == .terrorist }
        let ctExclusiveWeapons = allWeapons.filter { $0.faction == .counterTerrorist }

        let tKills = tExclusiveWeapons.reduce(0) { $0 + $1.kills }
        let ctKills = ctExclusiveWeapons.reduce(0) { $0 + $1.kills }
        let totalExclusiveKills = max(tKills + ctKills, 1)

        let hasDirectSchemaWins = (explicitTerroristWins != nil || explicitCounterTerroristWins != nil)
        let resolvedTWins: Int
        let resolvedCTWins: Int

        if let tW = explicitTerroristWins, let ctW = explicitCounterTerroristWins, (tW + ctW) > 0 {
            resolvedTWins = tW
            resolvedCTWins = ctW
        } else {
            // Derive side win split proportionally from total rounds won and side-exclusive rifle/SMG/pistol engagement share
            let tRatio = Double(tKills) / Double(totalExclusiveKills)
            resolvedTWins = Int((Double(roundsWon) * tRatio).rounded())
            resolvedCTWins = max(roundsWon - resolvedTWins, 0)
        }

        let totalSideWins = max(resolvedTWins + resolvedCTWins, 1)
        let tDominance = (Double(resolvedTWins) / Double(totalSideWins)) * 100.0
        let ctDominance = (Double(resolvedCTWins) / Double(totalSideWins)) * 100.0

        switch faction {
        case .both:
            let totalObjectives = bombsPlanted + bombsDefused
            let objRate = roundsPlayed > 0 ? (Double(totalObjectives) / Double(roundsPlayed)) * 100.0 : 0.0
            return FactionPerformanceSummary(
                faction: .both,
                hasDirectRoundWinsInSchema: hasDirectSchemaWins,
                terroristRoundsWon: resolvedTWins,
                counterTerroristRoundsWon: resolvedCTWins,
                selectedSideRoundsWon: roundsWon,
                dominancePercentage: winRatePercentage,
                terroristDominancePercentage: tDominance,
                counterTerroristDominancePercentage: ctDominance,
                factionWeaponKills: totalKills,
                factionShotsFired: shotsFired,
                factionShotsHit: shotsHit,
                factionAccuracyPercentage: accuracyPercentage,
                objectiveCount: totalObjectives,
                objectiveTitle: "OBJECTIVES",
                objectiveEfficiencyPercent: objRate,
                objectiveEfficiencySubtitle: "\(bombsPlanted.formatted()) Planted • \(bombsDefused.formatted()) Defused"
            )

        case .terrorist:
            let tFired = tExclusiveWeapons.reduce(0) { $0 + $1.shotsFired }
            let tHit = tExclusiveWeapons.reduce(0) { $0 + $1.shotsHit }
            let tAcc = tFired > 0 ? min((Double(tHit) / Double(tFired)) * 100.0, 100.0) : accuracyPercentage
            let plantEfficiency = resolvedTWins > 0 ? min((Double(bombsPlanted) / Double(resolvedTWins)) * 100.0, 100.0) : 0.0

            return FactionPerformanceSummary(
                faction: .terrorist,
                hasDirectRoundWinsInSchema: hasDirectSchemaWins,
                terroristRoundsWon: resolvedTWins,
                counterTerroristRoundsWon: resolvedCTWins,
                selectedSideRoundsWon: resolvedTWins,
                dominancePercentage: tDominance,
                terroristDominancePercentage: tDominance,
                counterTerroristDominancePercentage: ctDominance,
                factionWeaponKills: tKills,
                factionShotsFired: tFired,
                factionShotsHit: tHit,
                factionAccuracyPercentage: tAcc,
                objectiveCount: bombsPlanted,
                objectiveTitle: "BOMBS PLANTED",
                objectiveEfficiencyPercent: plantEfficiency,
                objectiveEfficiencySubtitle: String(format: "%.1f%% Plant-to-Win Ratio", plantEfficiency)
            )

        case .counterTerrorist:
            let ctFired = ctExclusiveWeapons.reduce(0) { $0 + $1.shotsFired }
            let ctHit = ctExclusiveWeapons.reduce(0) { $0 + $1.shotsHit }
            let ctAcc = ctFired > 0 ? min((Double(ctHit) / Double(ctFired)) * 100.0, 100.0) : accuracyPercentage
            let defuseEfficiency = bombsPlanted > 0
                ? min((Double(bombsDefused) / Double(max(resolvedCTWins, 1))) * 100.0, 100.0)
                : 0.0

            return FactionPerformanceSummary(
                faction: .counterTerrorist,
                hasDirectRoundWinsInSchema: hasDirectSchemaWins,
                terroristRoundsWon: resolvedTWins,
                counterTerroristRoundsWon: resolvedCTWins,
                selectedSideRoundsWon: resolvedCTWins,
                dominancePercentage: ctDominance,
                terroristDominancePercentage: tDominance,
                counterTerroristDominancePercentage: ctDominance,
                factionWeaponKills: ctKills,
                factionShotsFired: ctFired,
                factionShotsHit: ctHit,
                factionAccuracyPercentage: ctAcc,
                objectiveCount: bombsDefused,
                objectiveTitle: "BOMBS DEFUSED",
                objectiveEfficiencyPercent: defuseEfficiency,
                objectiveEfficiencySubtitle: String(format: "%.1f%% Defuse-to-Win Ratio", defuseEfficiency)
            )
        }
    }
}