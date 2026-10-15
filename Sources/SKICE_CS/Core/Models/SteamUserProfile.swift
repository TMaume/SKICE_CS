import Foundation
import Observation

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

/// Input validation utilities for Steam credentials.
public enum SteamCredentialsValidator: Sendable {
    /// Validates a 17-digit SteamID64 starting with the standard individual account prefix `7656119`.
    public static func isValidSteamID64(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 17,
              trimmed.hasPrefix("7656119"),
              trimmed.allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    /// Validates a 32-character hexadecimal Steam Web API Key.
    public static func isValidWebAPIKey(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 32 else { return false }
        return trimmed.allSatisfy(\.isHexDigit)
    }
}

/// Reactive state container managing local Steam credentials and profile synchronization.
@Observable
@MainActor
public final class SteamSessionStore {
    public private(set) var storedSteamID64: String?
    public private(set) var hasStoredAPIKey: Bool = false
    public private(set) var maskedAPIKey: String?
    public private(set) var activeProfile: SteamUserProfile?
    public private(set) var isLoadingNetwork: Bool = false
    public var statusMessage: String?
    public var errorMessage: String?

    private let keychain: KeychainHelper

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
        reloadFromKeychain()
    }

    /// Reloads persisted credentials from the local iOS Keychain.
    public func reloadFromKeychain() {
        errorMessage = nil

        if let id = try? keychain.read(for: .steamID64), !id.isEmpty {
            storedSteamID64 = id
            if activeProfile?.steamID64 != id {
                activeProfile = SteamUserProfile(
                    steamID64: id,
                    personaName: "Operator #\(id.suffix(4))",
                    profileURL: URL(string: "https://steamcommunity.com/profiles/\(id)"),
                    personaState: .online,
                    visibilityState: .publicProfile
                )
            }
        } else {
            storedSteamID64 = nil
            activeProfile = nil
        }

        if let apiKey = try? keychain.read(for: .webAPIKey), !apiKey.isEmpty {
            hasStoredAPIKey = true
            let prefix = apiKey.prefix(4)
            let suffix = apiKey.suffix(4)
            maskedAPIKey = "\(prefix)••••••••••••••••••••••••\(suffix)"
        } else {
            hasStoredAPIKey = false
            maskedAPIKey = nil
        }
    }

    /// Validates and persists the user's SteamID64 and optional Web API Key in the Keychain.
    public func saveCredentials(steamID64: String, webAPIKey: String) {
        errorMessage = nil
        statusMessage = nil

        let cleanSteamID = steamID64.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = webAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SteamCredentialsValidator.isValidSteamID64(cleanSteamID) else {
            errorMessage = "Invalid SteamID64 format. Expected 17 digits starting with 7656119."
            return
        }

        if !cleanAPIKey.isEmpty && !SteamCredentialsValidator.isValidWebAPIKey(cleanAPIKey) {
            errorMessage = "Invalid Steam Web API Key. Expected 32 hexadecimal characters."
            return
        }

        do {
            try keychain.save(cleanSteamID, for: .steamID64)
            if !cleanAPIKey.isEmpty {
                try keychain.save(cleanAPIKey, for: .webAPIKey)
            }
            reloadFromKeychain()
            statusMessage = "Credentials encrypted and saved to local iOS Keychain."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears all stored credentials from the local iOS Keychain.
    public func clearCredentials() {
        errorMessage = nil
        statusMessage = nil

        do {
            try keychain.clearAll()
            reloadFromKeychain()
            statusMessage = "Local Keychain credentials cleared."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Performs a Direct-to-API request to `api.steampowered.com` to fetch live profile data.
    public func syncProfileFromSteamWebAPI() async {
        errorMessage = nil
        statusMessage = nil

        guard let steamID = storedSteamID64 else {
            errorMessage = "No SteamID64 found in Keychain."
            return
        }

        guard let apiKey = try? keychain.read(for: .webAPIKey), !apiKey.isEmpty else {
            errorMessage = "A local Steam Web API Key is required to query GetPlayerSummaries."
            return
        }

        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamids", value: steamID)
        ]

        guard let url = components?.url else {
            errorMessage = "Failed to construct Steam Web API URL."
            return
        }

        isLoadingNetwork = true
        defer { isLoadingNetwork = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid HTTP response from Steam."
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                errorMessage = "Steam Web API returned HTTP \(httpResponse.statusCode). Verify your API key."
                return
            }

            let decoded = try JSONDecoder().decode(SteamPlayerSummariesEnvelope.self, from: data)
            guard let player = decoded.response.players.first else {
                errorMessage = "No player summary found for SteamID64 \(steamID)."
                return
            }

            activeProfile = player
            statusMessage = "Steam profile synced directly from Valve servers."
        } catch {
            errorMessage = "Direct-to-API sync failed: \(error.localizedDescription)"
        }
    }
}