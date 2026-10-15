import Foundation
import Security
import SwiftUI

// MARK: - Keychain & Settings Storage Bridge for Module 4

public enum StatsCredentialsStore {
    private static let statsKeychainService = "com.dtl21.SKICEcs.stats"
    private static let steamIDKey = "steamID64"
    private static let steamAPIKey = "steamWebAPIKey"
    private static let faceitIdentifierKey = "faceitPlayerIdentifier"
    private static let faceitAPIKey = "faceitOpenAPIKey"

    public static func readSteamID64() -> String {
        let allItems = dumpAppKeychainStrings()

        // 1. Prefer an explicit 17-digit SteamID64 starting with 7656
        for (_, value) in allItems {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSteamID64Format(trimmed) {
                return trimmed
            }
        }

        // 2. Fallback to account name matching
        for (account, value) in allItems {
            let lowerAccount = account.lowercased()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if lowerAccount.contains("steamid") || lowerAccount.contains("steam_id") {
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return (UserDefaults.standard.string(forKey: steamIDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func readSteamWebAPIKey() -> String {
        let allItems = dumpAppKeychainStrings()

        // 1. Strict match: 32-character hexadecimal Steam Web API Key
        for (account, value) in allItems {
            let lowerAccount = account.lowercased()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lowerAccount.contains("faceit"), !isSteamID64Format(trimmed) else { continue }

            if trimmed.count == 32, trimmed.allSatisfy(\.isHexDigit) {
                logResolvedKey(trimmed, source: "Keychain account '\(account)' (32-hex)")
                return trimmed
            }
        }

        // 2. Secondary match: any non-SteamID64, non-FACEIT value in an API key slot
        for (account, value) in allItems {
            let lowerAccount = account.lowercased()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lowerAccount.contains("faceit"),
                  !lowerAccount.contains("steamid"),
                  !lowerAccount.contains("steam_id"),
                  !isSteamID64Format(trimmed),
                  !trimmed.isEmpty else {
                continue
            }

            if lowerAccount.contains("api") || lowerAccount.contains("web") || lowerAccount.contains("secret") {
                logResolvedKey(trimmed, source: "Keychain account '\(account)'")
                return trimmed
            }
        }

        // 3. Fallback: if there are multiple Keychain items and one is NOT the 17-digit SteamID64
        for (account, value) in allItems {
            let lowerAccount = account.lowercased()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lowerAccount.contains("faceit"),
                  !isSteamID64Format(trimmed),
                  trimmed.count >= 16 else {
                continue
            }
            logResolvedKey(trimmed, source: "Keychain fallback '\(account)'")
            return trimmed
        }

        // 4. Check UserDefaults
        let defaultsKey = (UserDefaults.standard.string(forKey: steamAPIKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultsKey.isEmpty, !isSteamID64Format(defaultsKey) {
            logResolvedKey(defaultsKey, source: "UserDefaults")
            return defaultsKey
        }

        let allAccounts = allItems.map { "\($0.account) (len: \($0.value.count))" }.joined(separator: ", ")
        DebugLogger.shared.log("[KeychainBridge] No valid Steam Web API Key found. Keychain slots inspected: [\(allAccounts)]")
        return ""
    }

    public static func readFaceitIdentifier() -> String {
        if let val = readKeychainString(account: faceitIdentifierKey), !val.isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (UserDefaults.standard.string(forKey: faceitIdentifierKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func saveFaceitIdentifier(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveKeychainString(trimmed, account: faceitIdentifierKey)
        UserDefaults.standard.set(trimmed, forKey: faceitIdentifierKey)
    }

    public static func readFaceitAPIKey() -> String {
        if let val = readKeychainString(account: faceitAPIKey), !val.isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (UserDefaults.standard.string(forKey: faceitAPIKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func saveFaceitAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveKeychainString(trimmed, account: faceitAPIKey)
        UserDefaults.standard.set(trimmed, forKey: faceitAPIKey)
    }

    // MARK: - Validation & Diagnostic Helpers

    private static func isSteamID64Format(_ text: String) -> Bool {
        text.count == 17 && text.hasPrefix("7656") && text.allSatisfy(\.isNumber)
    }

    private static func logResolvedKey(_ key: String, source: String) {
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        DebugLogger.shared.log("[KeychainBridge] Resolved Steam Web API Key from \(source): \(prefix)...\(suffix) (len: \(key.count))")
    }

    // MARK: - Direct iOS Keychain Helpers (Security Framework)

    private static func saveKeychainString(_ value: String, account: String) {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: statsKeychainService,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(baseQuery as CFDictionary)

        guard !value.isEmpty else { return }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readKeychainString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: statsKeychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func dumpAppKeychainStrings() -> [(account: String, value: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict in
            guard let data = dict[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            let account = (dict[kSecAttrAccount as String] as? String) ?? ""
            return (account: account, value: value)
        }
    }
}

// MARK: - DebugLogger Network Tracing Helper

extension DebugLogger {
    public func logStatsNetworkRequest(_ request: URLRequest, tag: String) {
        let method = request.httpMethod ?? "GET"
        let sanitizedURL = Self.redactSecrets(in: request.url?.absoluteString ?? "unknown")
        var sanitizedHeaders = request.allHTTPHeaderFields ?? [:]
        if sanitizedHeaders["Authorization"] != nil {
            sanitizedHeaders["Authorization"] = "Bearer <REDACTED>"
        }
        log("[\(tag)] -> \(method) \(sanitizedURL) | Headers: \(sanitizedHeaders)")
    }

    public func logStatsNetworkResponse(
        url: URL?,
        statusCode: Int,
        byteCount: Int,
        durationMs: Int,
        bodyPreview: String? = nil,
        tag: String
    ) {
        let sanitizedURL = Self.redactSecrets(in: url?.absoluteString ?? "unknown")
        if let bodyPreview, !bodyPreview.isEmpty {
            log("[\(tag)] <- HTTP \(statusCode) (\(byteCount) bytes in \(durationMs) ms) | \(sanitizedURL) | Body: \(bodyPreview)")
        } else {
            log("[\(tag)] <- HTTP \(statusCode) (\(byteCount) bytes in \(durationMs) ms) | \(sanitizedURL)")
        }
    }

    public func logStatsError(_ message: String, tag: String) {
        log("[\(tag)] ERROR: \(message)")
    }

    private static func redactSecrets(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([?&]key=)[^&]+", options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1<REDACTED>")
    }
}

// MARK: - AppTheme Palette Extensions for Stats Dashboard

extension AppTheme {
    public static var statsBackground: Color {
        Color(red: 0.04, green: 0.05, blue: 0.07)
    }

    public static var statsCardSurface: Color {
        Color(red: 0.09, green: 0.11, blue: 0.15)
    }

    public static var statsCardBorder: Color {
        Color.white.opacity(0.08)
    }

    public static var statsAccentOrange: Color {
        Color(red: 1.00, green: 0.42, blue: 0.00)
    }

    public static var statsAccentBlue: Color {
        Color(red: 0.24, green: 0.62, blue: 1.00)
    }

    public static var statsPositiveGreen: Color {
        Color(red: 0.18, green: 0.82, blue: 0.48)
    }

    public static var statsDangerRed: Color {
        Color(red: 0.95, green: 0.28, blue: 0.30)
    }

    public static func faceitLevelColor(_ level: Int) -> Color {
        switch level {
        case 1:
            return Color(white: 0.78)
        case 2, 3:
            return Color(red: 0.18, green: 0.82, blue: 0.48)
        case 4, 5, 6, 7:
            return Color(red: 0.98, green: 0.78, blue: 0.18)
        case 8, 9:
            return Color(red: 1.00, green: 0.45, blue: 0.10)
        case 10:
            return Color(red: 0.94, green: 0.18, blue: 0.22)
        default:
            return Color.gray
        }
    }
}