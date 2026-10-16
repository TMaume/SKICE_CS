import Foundation

/// One ranked-ladder entry from the Game Coordinator, decoded from
/// CMsgGCCStrike15_v2_MatchmakingGC2ClientHello (ranking / rankings).
///
/// Field numbers come from Valve's cstrike15_gcmessages.proto (PlayerRankingInfo),
/// so they are authoritative. The *semantic* mapping is community-decoded and
/// marked PROVISIONAL below: it must be confirmed against a live on-device
/// payload before the number is trusted.
/// One per-map competitive rank entry, decoded from PlayerRankingInfo field 13
/// (per_map_rank). Field numbers are authoritative (cstrike15_gcmessages.proto).
/// The numeric map_id -> name mapping lives in SteamMapCatalog and is
/// PROVISIONAL: verified only against community references, not a live payload.
public struct PerMapRank: Codable, Sendable, Equatable {
    /// Numeric Game Coordinator map id (see SteamMapCatalog.gcMapIDToCode).
    public let mapID: UInt32
    /// The 18-tier competitive rank id on this map.
    public let rankID: UInt32
    public let wins: UInt32

    public init(mapID: UInt32, rankID: UInt32, wins: UInt32) {
        self.mapID = mapID
        self.rankID = rankID
        self.wins = wins
    }
}

public struct PlayerRankingInfo: Codable, Sendable, Equatable {
    public let accountID: UInt32
    /// For Premier this is believed to carry the numeric CS Rating directly.
    public let rankID: UInt32
    public let wins: UInt32
    /// Signed rating change from the most recent match.
    public let rankChange: Float
    /// Which ladder this entry describes (competitive / wingman / Premier).
    public let rankTypeID: UInt32
    /// Packed 64-bit window stats (recent results) — raw, semantics unverified.
    public let rankWindowStats: UInt64
    public let leaderboardName: String?
    public let rankIfWin: UInt32
    public let rankIfLose: UInt32
    public let rankIfTie: UInt32
    public let highestRank: UInt32
    public let rankExpiry: UInt32
    /// Per-map competitive ranks (field 13). Empty for Premier and Wingman ladders.
    public let perMapRanks: [PerMapRank]

    public init(
        accountID: UInt32,
        rankID: UInt32,
        wins: UInt32,
        rankChange: Float,
        rankTypeID: UInt32,
        rankWindowStats: UInt64,
        leaderboardName: String?,
        rankIfWin: UInt32,
        rankIfLose: UInt32,
        rankIfTie: UInt32,
        highestRank: UInt32,
        rankExpiry: UInt32,
        perMapRanks: [PerMapRank] = []
    ) {
        self.accountID = accountID
        self.rankID = rankID
        self.wins = wins
        self.rankChange = rankChange
        self.rankTypeID = rankTypeID
        self.rankWindowStats = rankWindowStats
        self.leaderboardName = leaderboardName
        self.rankIfWin = rankIfWin
        self.rankIfLose = rankIfLose
        self.rankIfTie = rankIfTie
        self.highestRank = highestRank
        self.rankExpiry = rankExpiry
        self.perMapRanks = perMapRanks
    }

    /// PROVISIONAL: CS2's Premier ladder is rank_type_id 11 (community-decoded;
    /// confirm on a live payload). For Premier, rankID is believed to hold the
    /// numeric CS Rating directly.
    public var isPremier: Bool { rankTypeID == 11 }

    /// PROVISIONAL: CS2's competitive ladder is rank_type_id 6 (community-decoded).
    public var isCompetitive: Bool { rankTypeID == 6 }

    /// PROVISIONAL: CS2's Wingman ladder is rank_type_id 7 (community-decoded).
    public var isWingman: Bool { rankTypeID == 7 }

    /// The numeric Premier rating, or nil for non-Premier ladders.
    public var premierRating: Int? {
        isPremier ? Int(rankID) : nil
    }
}
