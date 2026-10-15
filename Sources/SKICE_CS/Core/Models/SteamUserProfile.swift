import Foundation
import Observation

/// État de connexion d'un profil sur le réseau Steam (valeurs officielles Steam Web API).
public enum SteamPersonaState: Int, Codable, Sendable, CaseIterable {
    case offline = 0
    case online = 1
    case busy = 2
    case away = 3
    case snooze = 4
    case lookingToTrade = 5
    case lookingToPlay = 6

    public var label: String {
        switch self {
        case .offline: return "Hors ligne"
        case .online: return "En ligne"
        case .busy: return "Occupé"
        case .away: return "Absent"
        case .snooze: return "En veille"
        case .lookingToTrade: return "Cherche à échanger"
        case .lookingToPlay: return "Cherche à jouer"
        }
    }
}

/// Niveau de visibilité du profil communautaire Steam.
public enum SteamCommunityVisibilityState: Int, Codable, Sendable {
    case privateProfile = 1
    case friendsOnly = 2
    case publicProfile = 3

    public var label: String {
        switch self {
        case .privateProfile: return "Privé"
        case .friendsOnly: return "Amis uniquement"
        case .publicProfile: return "Public"
        }
    }
}

/// Modèle représentant le profil Steam d'un joueur CS2.
/// Compatible avec le décodage direct de `ISteamUser/GetPlayerSummaries/v0002/`.
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

    /// Indique si l'utilisateur est actuellement en jeu sur Counter-Strike 2 (AppID 730).
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

/// Enveloppe JSON renvoyée par l'endpoint `ISteamUser/GetPlayerSummaries/v0002/`.
public struct SteamPlayerSummariesEnvelope: Decodable, Sendable {
    public struct InnerResponse: Decodable, Sendable {
        public let players: [SteamUserProfile]
    }
    public let response: InnerResponse
}

/// Utilitaire de validation de format pour les identifiants Steam et clés API.
public enum SteamCredentialsValidator: Sendable {
    /// Vérifie qu'un SteamID64 possède exactement 17 chiffres et débute par le préfixe individuel `7656119`.
    public static func isValidSteamID64(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 17,
              trimmed.hasPrefix("7656119"),
              trimmed.allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    /// Vérifie qu'une clé Steam Web API est composée de 32 caractères hexadécimaux.
    public static func isValidSteamAPIKey(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 32 else { return false }
        return trimmed.allSatisfy { $0.isHexDigit }
    }
}

/// Gestionnaire d'état d'authentification et de profil utilisant le framework Observation (`@Observable`).
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

    /// Recharge l'état depuis le Keychain local de l'appareil.
    public func reloadFromKeychain() {
        errorMessage = nil

        if let id = try? keychain.read(for: .steamID64), !id.isEmpty {
            storedSteamID64 = id
            if activeProfile?.steamID64 != id {
                activeProfile = SteamUserProfile(
                    steamID64: id,
                    personaName: "Opérateur #\(id.suffix(4))",
                    profileURL: URL(string: "https://steamcommunity.com/profiles/\(id)"),
                    personaState: .online,
                    visibilityState: .publicProfile
                )
            }
        } else {
            storedSteamID64 = nil
            activeProfile = nil
        }

        if let apiKey = try? keychain.read(for: .steamWebAPIKey), !apiKey.isEmpty {
            hasStoredAPIKey = true
            let prefix = apiKey.prefix(4)
            let suffix = apiKey.suffix(4)
            maskedAPIKey = "\(prefix)••••••••••••••••••••••••\(suffix)"
        } else {
            hasStoredAPIKey = false
            maskedAPIKey = nil
        }
    }

    /// Valide et enregistre le SteamID64 et la clé API optionnelle dans le Keychain local.
    public func saveCredentials(steamID64: String, apiKey: String) {
        errorMessage = nil
        statusMessage = nil

        let cleanSteamID = steamID64.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SteamCredentialsValidator.isValidSteamID64(cleanSteamID) else {
            errorMessage = "Format SteamID64 invalide. Attendu : 17 chiffres commençant par 7656119."
            return
        }

        if !cleanAPIKey.isEmpty && !SteamCredentialsValidator.isValidSteamAPIKey(cleanAPIKey) {
            errorMessage = "Format de clé API Steam invalide. Attendu : 32 caractères hexadécimaux."
            return
        }

        do {
            try keychain.save(cleanSteamID, for: .steamID64)
            if !cleanAPIKey.isEmpty {
                try keychain.save(cleanAPIKey, for: .steamWebAPIKey)
            }
            reloadFromKeychain()
            statusMessage = "Identifiants chiffrés et sauvegardés dans le Keychain iOS."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Supprime toutes les informations d'authentification du Keychain local.
    public func purgeCredentials() {
        errorMessage = nil
        statusMessage = nil

        do {
            try keychain.clearAll()
            reloadFromKeychain()
            statusMessage = "Trousseau Keychain purgé avec succès."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Effectue une requête Direct-to-API vers `api.steampowered.com` pour synchroniser le profil public.
    public func syncProfileFromSteamWebAPI() async {
        errorMessage = nil
        statusMessage = nil

        guard let steamID = storedSteamID64 else {
            errorMessage = "Aucun SteamID64 enregistré dans le Keychain."
            return
        }

        guard let apiKey = try? keychain.read(for: .steamWebAPIKey), !apiKey.isEmpty else {
            errorMessage = "Une clé Steam Web API locale est requise pour interroger l'endpoint GetPlayerSummaries."
            return
        }

        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamids", value: steamID)
        ]

        guard let url = components?.url else {
            errorMessage = "URL de requête Steam Web API invalide."
            return
        }

        isLoadingNetwork = true
        defer { isLoadingNetwork = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Réponse réseau invalide."
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                errorMessage = "Erreur Steam Web API (HTTP \(httpResponse.statusCode)). Vérifiez votre clé API."
                return
            }

            let decoded = try JSONDecoder().decode(SteamPlayerSummariesEnvelope.self, from: data)
            guard let player = decoded.response.players.first else {
                errorMessage = "Aucun profil trouvé pour le SteamID64 \(steamID)."
                return
            }

            activeProfile = player
            statusMessage = "Profil Steam synchronisé en direct depuis les serveurs Valve."
        } catch {
            errorMessage = "Échec de synchronisation directe : \(error.localizedDescription)"
        }
    }
}