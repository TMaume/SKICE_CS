import Foundation
import Observation

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
            let request = APIClient.makeRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let response = try await APIClient.shared.send(request)

            guard (200...299).contains(response.statusCode) else {
                errorMessage = "Steam Web API returned HTTP \(response.statusCode). Verify your API key."
                return
            }

            let decoded = try JSONDecoder().decode(SteamPlayerSummariesEnvelope.self, from: response.data)
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
