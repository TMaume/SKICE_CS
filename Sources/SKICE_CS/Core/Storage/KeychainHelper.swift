import Foundation
import Security

/// Keys identifying user secrets stored locally in the iOS Keychain.
public enum KeychainKey: String, CaseIterable, Sendable {
    case steamID64 = "com.skice.cs2.keychain.steamid64"
    case webAPIKey = "com.skice.cs2.keychain.webapikey"
    case steamRefreshToken = "com.skice.cs2.keychain.steamrefreshtoken"
    case steamAccessToken = "com.skice.cs2.keychain.steamaccesstoken"
    case steamSessionSteamID = "com.skice.cs2.keychain.steamsessionsteamid"
    case steamAccountName = "com.skice.cs2.keychain.steamaccountname"
    case steamGuardData = "com.skice.cs2.keychain.steamguarddata"
    case steamRememberAccount = "com.skice.cs2.keychain.steamrememberaccount"
    case steamRememberPassword = "com.skice.cs2.keychain.steamrememberpassword"
    case faceitAPIKey = "com.skice.cs2.keychain.faceitapikey"
}

/// Typed errors for iOS Keychain operations.
public enum KeychainError: LocalizedError, Sendable, Equatable {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode string data to UTF-8 for Keychain storage."
        case .decodingFailed:
            return "Failed to decode data retrieved from the Keychain."
        case .itemNotFound:
            return "Requested credential was not found in the local Keychain."
        case .unexpectedStatus(let status):
            return "iOS Keychain system error (OSStatus: \(status))."
        }
    }
}

/// Thread-safe, Zero-Trust local credential manager backed by iOS Keychain Services.
/// Credentials never leave the device toward any intermediate backend server.
public struct KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let serviceIdentifier = "com.skice.cs2.companion"

    private init() {}

    // MARK: - CRUD Operations

    /// Saves or updates a string value in the local iOS Keychain.
    public func save(_ value: String, for key: KeychainKey) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key.rawValue
        ]

        let existingStatus = SecItemCopyMatching(baseQuery as CFDictionary, nil)

        switch existingStatus {
        case errSecSuccess:
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                attributesToUpdate as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }

        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }

        default:
            throw KeychainError.unexpectedStatus(existingStatus)
        }
    }

    /// Reads a string value from the local iOS Keychain for the specified key.
    public func read(for key: KeychainKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data,
              let stringValue = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return stringValue
    }

    /// Checks whether a value exists in the Keychain for the given key.
    public func exists(for key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: false
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Deletes a specific key from the iOS Keychain.
    public func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes all SKICE_CS credentials from the local Keychain.
    public func clearAll() throws {
        for key in KeychainKey.allCases {
            try delete(for: key)
        }
    }
}