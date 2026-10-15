import Foundation

/// Errors raised by the persisted Steam session.
public enum SteamSessionError: LocalizedError, Sendable {
    case noRefreshToken
    case noSteamID
    case accessTokenNotAJWT

    public var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No Steam refresh token is stored on this device."
        case .noSteamID:
            return "The Steam session does not record an account SteamID64."
        case .accessTokenNotAJWT:
            return "The Steam access token is not a decodable JWT."
        }
    }
}

/// Keychain-backed storage for the Tier B Steam session (refresh token, access
/// token, account identity, guard data).
///
/// Separate from the Tier A credentials (SteamID64 + Web API key) so signing out
/// of the session never disturbs the key-based setup. Tokens are only ever
/// written here and only ever read back for direct-to-Steam requests
/// (ROADMAP section 0.2, ADR-04).
public struct SteamAuthTokenStore: Sendable {
    public static let shared = SteamAuthTokenStore()

    private let keychain: KeychainHelper

    private enum DefaultsKey {
        static let accessTokenExpiry = "com.dtl21.SKICEcs.steamAccessTokenExpiry"
        static let accountName = "com.dtl21.SKICEcs.steamAccountName"
    }

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    // MARK: - Reads

    public var refreshToken: String? {
        value(for: .steamRefreshToken)
    }

    public var accessToken: String? {
        value(for: .steamAccessToken)
    }

    public var sessionSteamID64: String? {
        value(for: .steamSessionSteamID)
    }

    public var accountName: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.accountName)
    }

    public var storedGuardData: Data? {
        guard let token = value(for: .steamGuardData) else { return nil }
        return Data(base64Encoded: token)
    }

    /// True when a refresh token is on the device: the session survives app
    /// restarts and can mint new access tokens.
    public var hasPersistedSession: Bool {
        refreshToken != nil
    }

    // MARK: - Remembered login (quick re-connect)

    /// The account name remembered from the last password sign-in, if any.
    public var rememberedAccountName: String? {
        value(for: .steamRememberAccount)
    }

    /// The password remembered from the last password sign-in, if any.
    public var rememberedPassword: String? {
        value(for: .steamRememberPassword)
    }

    /// Saves (or, with an empty value, clears) the remembered login for quick
    /// re-connect. Stored only in the Keychain.
    public func saveRememberedCredentials(accountName: String, password: String) throws {
        let account = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !password.isEmpty else {
            try clearRememberedCredentials()
            return
        }
        try keychain.save(account, for: .steamRememberAccount)
        try keychain.save(password, for: .steamRememberPassword)
    }

    /// Forgets the remembered login.
    public func clearRememberedCredentials() throws {
        try keychain.delete(for: .steamRememberAccount)
        try keychain.delete(for: .steamRememberPassword)
    }

    /// Expiry of the stored access token, read from its JWT payload.
    public var accessTokenExpiry: Date? {
        guard let raw = UserDefaults.standard.object(forKey: DefaultsKey.accessTokenExpiry) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: raw)
    }

    /// True when the access token is missing or past its JWT expiry.
    public var isAccessTokenExpired: Bool {
        guard accessToken != nil else { return true }
        guard let expiry = accessTokenExpiry else { return false }
        return expiry <= Date()
    }

    // MARK: - Writes

    /// Persists a full session after a successful login or token refresh.
    public func save(
        accessToken: String,
        refreshToken: String?,
        steamID64: String?,
        accountName: String?,
        guardData: Data?
    ) throws {
        try keychain.save(accessToken, for: .steamAccessToken)

        if let refreshToken, !refreshToken.isEmpty {
            try keychain.save(refreshToken, for: .steamRefreshToken)
        }
        if let steamID64, !steamID64.isEmpty {
            try keychain.save(steamID64, for: .steamSessionSteamID)
        }
        if let guardData, !guardData.isEmpty {
            try keychain.save(guardData.base64EncodedString(), for: .steamGuardData)
        }
        if let accountName, !accountName.isEmpty {
            UserDefaults.standard.set(accountName, forKey: DefaultsKey.accountName)
        }

        saveAccessTokenExpiry(for: accessToken)
    }

    /// Updates only the access token, keeping the refresh token in place.
    public func saveAccessToken(_ token: String) throws {
        try keychain.save(token, for: .steamAccessToken)
        saveAccessTokenExpiry(for: token)
    }

    /// Removes every trace of the Steam session from the device.
    public func clear() throws {
        try keychain.delete(for: .steamAccessToken)
        try keychain.delete(for: .steamRefreshToken)
        try keychain.delete(for: .steamSessionSteamID)
        try keychain.delete(for: .steamAccountName)
        try keychain.delete(for: .steamGuardData)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.accountName)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.accessTokenExpiry)
    }

    // MARK: - JWT inspection

    /// Reads the exp claim out of an access token without verifying the
    /// signature: the token is only ever presented back to Steam, which is the
    /// only party that can validate it.
    public static func expiry(ofJWT token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private func saveAccessTokenExpiry(for token: String) {
        if let expiry = Self.expiry(ofJWT: token) {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: DefaultsKey.accessTokenExpiry)
        }
    }

    private func value(for key: KeychainKey) -> String? {
        guard let raw = try? keychain.read(for: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
