import Foundation

/// Online status of a Steam user account as returned by the Steam Web API.
public enum SteamPersonaState: Int, Codable, Sendable, CaseIterable {
    case offline = 0
    case online = 1
    case busy = 2
    case away = 3
    case snooze = 4
    case lookingToTrade = 5
    case lookingToPlay = 6

    public var displayName: String {
        switch self {
        case .offline: return "Offline"
        case .online: return "Online"
        case .busy: return "Busy"
        case .away: return "Away"
        case .snooze: return "Snooze"
        case .lookingToTrade: return "Looking to Trade"
        case .lookingToPlay: return "Looking to Play"
        }
    }
}

/// Community visibility state of a Steam profile.
public enum SteamCommunityVisibilityState: Int, Codable, Sendable {
    case privateProfile = 1
    case friendsOnly = 2
    case publicProfile = 3

    public var displayName: String {
        switch self {
        case .privateProfile: return "Private"
        case .friendsOnly: return "Friends Only"
        case .publicProfile: return "Public"
        }
    }
}

/// Represents a user's Steam identity and real-time connection state.
/// Conforms to `Codable` for direct decoding from `ISteamUser/GetPlayerSummaries/v0002/`.
public struct SteamUserProfile: Codable, Identifiable, Equatable, Sendable {
    public let steamID64: String
    public var personaName: String
    public var profileURL: URL?
    public var avatarFullURL: URL?
    public var personaState: SteamPersonaState
    public var visibilityState: SteamCommunityVisibilityState
    public var countryCode: String?
    public var timeCreated: Date?
    public var currentGameID: String?
    public var currentGameName: String?
    public var lastSyncedAt: Date

    public var id: String { steamID64 }

    /// Indicates whether the user is currently in Counter-Strike 2 (AppID 730).
    public var isPlayingCS2: Bool {
        currentGameID == "730"
    }

    public init(
        steamID64: String,
        personaName: String,
        profileURL: URL? = nil,
        avatarFullURL: URL? = nil,
        personaState: SteamPersonaState = .offline,
        visibilityState: SteamCommunityVisibilityState = .publicProfile,
        countryCode: String? = nil,
        timeCreated: Date? = nil,
        currentGameID: String? = nil,
        currentGameName: String? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.steamID64 = steamID64
        self.personaName = personaName
        self.profileURL = profileURL
        self.avatarFullURL = avatarFullURL
        self.personaState = personaState
        self.visibilityState = visibilityState
        self.countryCode = countryCode
        self.timeCreated = timeCreated
        self.currentGameID = currentGameID
        self.currentGameName = currentGameName
        self.lastSyncedAt = lastSyncedAt
    }

    enum CodingKeys: String, CodingKey {
        case steamID64 = "steamid"
        case personaName = "personaname"
        case profileURL = "profileurl"
        case avatarFullURL = "avatarfull"
        case personaState = "personastate"
        case visibilityState = "communityvisibilitystate"
        case countryCode = "loccountrycode"
        case timeCreated = "timecreated"
        case currentGameID = "gameid"
        case currentGameName = "gameextrainfo"
        case lastSyncedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.steamID64 = try container.decode(String.self, forKey: .steamID64)
        self.personaName = try container.decode(String.self, forKey: .personaName)

        if let profileString = try container.decodeIfPresent(String.self, forKey: .profileURL) {
            self.profileURL = URL(string: profileString)
        } else {
            self.profileURL = nil
        }

        if let avatarString = try container.decodeIfPresent(String.self, forKey: .avatarFullURL) {
            self.avatarFullURL = URL(string: avatarString)
        } else {
            self.avatarFullURL = nil
        }

        let rawState = try container.decodeIfPresent(Int.self, forKey: .personaState) ?? 0
        self.personaState = SteamPersonaState(rawValue: rawState) ?? .offline

        let rawVisibility = try container.decodeIfPresent(Int.self, forKey: .visibilityState) ?? 1
        self.visibilityState = SteamCommunityVisibilityState(rawValue: rawVisibility) ?? .privateProfile

        self.countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)

        if let unixTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timeCreated) {
            self.timeCreated = Date(timeIntervalSince1970: unixTimestamp)
        } else {
            self.timeCreated = nil
        }

        self.currentGameID = try container.decodeIfPresent(String.self, forKey: .currentGameID)
        self.currentGameName = try container.decodeIfPresent(String.self, forKey: .currentGameName)
        self.lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt) ?? .now
    }
}

/// Top-level JSON envelope returned by `ISteamUser/GetPlayerSummaries/v0002/`.
public struct SteamPlayerSummariesEnvelope: Decodable, Sendable {
    public struct InnerResponse: Decodable, Sendable {
        public let players: [SteamUserProfile]
    }
    public let response: InnerResponse
}
