import Foundation

/// Central credential facade — the single source of truth for app secrets and
/// the (non-secret) FACEIT player identifier.
///
/// - Secrets (SteamID64, Steam Web API Key, FACEIT API Key) live exclusively in
///   the iOS Keychain via `KeychainHelper` and are never mirrored to UserDefaults.
/// - The FACEIT identifier (nickname / player ID) is not a secret, so it uses
///   UserDefaults.
public enum AppCredentialsStore {

    private enum DefaultsKey {
        static let faceitIdentifier = "com.dtl21.SKICEcs.faceitIdentifier"
    }

    // MARK: - Steam

    public static func readSteamID64() -> String {
        (try? KeychainHelper.shared.read(for: .steamID64))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func readSteamWebAPIKey() -> String {
        (try? KeychainHelper.shared.read(for: .webAPIKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - FACEIT

    public static func readFaceitAPIKey() -> String {
        (try? KeychainHelper.shared.read(for: .faceitAPIKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func saveFaceitAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? KeychainHelper.shared.delete(for: .faceitAPIKey)
            return
        }
        try? KeychainHelper.shared.save(trimmed, for: .faceitAPIKey)
    }

    public static func readFaceitIdentifier() -> String {
        (UserDefaults.standard.string(forKey: DefaultsKey.faceitIdentifier) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func saveFaceitIdentifier(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: DefaultsKey.faceitIdentifier)
    }
}
