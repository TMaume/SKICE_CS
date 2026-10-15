import Foundation
import Security

/// Clés identifiant les secrets stockés localement dans le Keychain iOS.
public enum KeychainKey: String, CaseIterable, Sendable {
    case steamID64 = "com.skice.cs2.keychain.steamid64"
    case steamWebAPIKey = "com.skice.cs2.keychain.steamwebapikey"
    case steamRefreshToken = "com.skice.cs2.keychain.steamrefreshtoken"
    case faceitAPIKey = "com.skice.cs2.keychain.faceitapikey"
}

/// Erreurs typées liées aux opérations du Keychain iOS.
public enum KeychainError: LocalizedError, Sendable, Equatable {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Impossible d'encoder la donnée en UTF-8 pour le Keychain."
        case .decodingFailed:
            return "Impossible de décoder la donnée issue du Keychain."
        case .itemNotFound:
            return "Aucune entrée trouvée dans le trousseau sécurisé."
        case .unexpectedStatus(let status):
            return "Erreur système Keychain iOS (OSStatus : \(status))."
        }
    }
}

/// Gestionnaire de stockage sécurisé local utilisant les API natives Security d'iOS.
/// Garantit une architecture Zero-Trust : aucun secret ne quitte l'appareil vers un backend tiers.
public struct KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let serviceIdentifier = "com.skice.cs2.companion"

    private init() {}

    // MARK: - Opérations génériques CRUD

    /// Sauvegarde ou met à jour une chaîne de caractères dans le Keychain iOS.
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

        let statusCheck = SecItemCopyMatching(baseQuery as CFDictionary, nil)

        switch statusCheck {
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
            var newItemQuery = baseQuery
            newItemQuery[kSecValueData as String] = data
            newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(newItemQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }

        default:
            throw KeychainError.unexpectedStatus(statusCheck)
        }
    }

    /// Lit une chaîne de caractères depuis le Keychain iOS pour une clé donnée.
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

    /// Vérifie si une valeur existe dans le Keychain pour la clé spécifiée.
    public func exists(for key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: false
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Supprime une entrée spécifique du Keychain iOS.
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

    /// Purge l'intégralité des secrets SKICE_CS stockés dans le Keychain local.
    public func clearAll() throws {
        for key in KeychainKey.allCases {
            try delete(for: key)
        }
    }
}