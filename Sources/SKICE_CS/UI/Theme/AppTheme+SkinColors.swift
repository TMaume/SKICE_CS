import SwiftUI
import Foundation

// MARK: - AppTheme Rarity & Exterior Color Extensions

public extension AppTheme {
    /// Returns the official CS2 rarity color, optionally using Steam's raw hex tag when valid.
    static func rarityColor(for rarity: SkinRarity, hexOverride: String? = nil) -> Color {
        if let hexOverride,
           let parsed = colorFromHex(hexOverride),
           rarity == .defaultRarity {
            return parsed
        }

        switch rarity {
        case .consumer:
            return Color(red: 0.69, green: 0.76, blue: 0.85) // #B0C3D9
        case .industrial:
            return Color(red: 0.37, green: 0.60, blue: 0.85) // #5E98D9
        case .milSpec:
            return Color(red: 0.29, green: 0.41, blue: 1.00) // #4B69FF
        case .restricted:
            return Color(red: 0.53, green: 0.28, blue: 1.00) // #8847FF
        case .classified:
            return Color(red: 0.83, green: 0.17, blue: 0.90) // #D32CE6
        case .covert:
            return Color(red: 0.92, green: 0.29, blue: 0.29) // #EB4B4B
        case .extraordinary:
            return Color(red: 0.92, green: 0.29, blue: 0.29) // #EB4B4B
        case .contraband:
            return Color(red: 0.89, green: 0.68, blue: 0.22) // #E4AE39
        case .defaultRarity:
            return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }

    /// Returns a semantic color for the exterior condition badge.
    static func exteriorColor(for exterior: SkinExterior) -> Color {
        switch exterior {
        case .factoryNew:
            return Color(red: 0.18, green: 0.80, blue: 0.44)
        case .minimalWear:
            return Color(red: 0.35, green: 0.78, blue: 0.65)
        case .fieldTested:
            return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .wellWorn:
            return Color(red: 0.90, green: 0.49, blue: 0.13)
        case .battleScarred:
            return Color(red: 0.91, green: 0.30, blue: 0.24)
        case .notPainted:
            return Color.gray
        }
    }

    /// Returns a semantic color for the trade restriction badge.
    static func tradeStatusColor(for status: SkinTradeStatus) -> Color {
        switch status {
        case .tradable:
            return AppTheme.Colors.statusSuccess
        case .tradeCooldown:
            return AppTheme.Colors.csOrange
        case .untradable:
            return Color(red: 0.58, green: 0.62, blue: 0.68)
        }
    }

    /// StatTrak™ signature orange color.
    static var statTrakOrange: Color {
        Color(red: 0.81, green: 0.42, blue: 0.20) // #CF6A32
    }

    /// Souvenir signature gold color.
    static var souvenirGold: Color {
        Color(red: 1.00, green: 0.84, blue: 0.00) // #FFD700
    }

    /// Parses a 6-character hex string into a SwiftUI `Color`.
    static func colorFromHex(_ hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let intVal = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}