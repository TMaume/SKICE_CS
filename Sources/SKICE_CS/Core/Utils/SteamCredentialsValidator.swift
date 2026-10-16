import Foundation

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
