import SwiftUI

/// Centralized CS2-inspired design system optimized for OLED displays.
public enum AppTheme {

    // MARK: - Color Palette

    public enum Colors {
        /// True OLED Black (#000000) for maximum contrast and battery efficiency.
        public static let oledBlack = Color(red: 0.0, green: 0.0, blue: 0.0)

        /// Dark gunmetal gray (#11141C) for primary tactical cards and containers.
        public static let gunmetalGray = Color(red: 0.067, green: 0.078, blue: 0.110)

        /// Elevated gunmetal surface (#1A1F2B) for text fields and interactive rows.
        public static let gunmetalElevated = Color(red: 0.102, green: 0.122, blue: 0.169)

        /// Subtle tactical border (#283042).
        public static let borderSubtle = Color(red: 0.157, green: 0.188, blue: 0.259)

        /// Counter-Strike 2 signature Orange / Terrorist faction accent (#E58E26).
        public static let csOrange = Color(red: 0.898, green: 0.557, blue: 0.149)

        /// Counter-Terrorist tactical Steel Blue accent (#4A78B5).
        public static let ctBlue = Color(red: 0.290, green: 0.471, blue: 0.710)

        /// Positive / VAC-Safe status green (#10B981).
        public static let statusSuccess = Color(red: 0.063, green: 0.725, blue: 0.506)

        /// Warning / Danger crimson (#EF4444).
        public static let statusDanger = Color(red: 0.937, green: 0.267, blue: 0.267)

        /// High-contrast primary text (#F3F4F6).
        public static let textPrimary = Color(red: 0.953, green: 0.957, blue: 0.965)

        /// Muted technical label text (#9CA3AF).
        public static let textSecondary = Color(red: 0.612, green: 0.639, blue: 0.686)

        /// Signature CS2 header gradient blending CS Orange and CT Blue over OLED Black.
        public static let headerGradient = LinearGradient(
            colors: [
                csOrange.opacity(0.22),
                ctBlue.opacity(0.14),
                oledBlack
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography

    public enum Fonts {
        public static let headerTitle = Font.system(size: 22, weight: .black, design: .default)
        public static let sectionTitle = Font.system(size: 13, weight: .bold, design: .monospaced)
        public static let bodyRegular = Font.system(size: 15, weight: .medium, design: .default)
        public static let metricMono = Font.system(size: 14, weight: .semibold, design: .monospaced)
        public static let captionMono = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
}

// MARK: - Reusable View Modifiers & Button Styles

/// Gunmetal tactical card modifier with fine border highlight.
public struct TacticalCardModifier: ViewModifier {
    let accentBorderColor: Color?

    public init(accentBorderColor: Color? = nil) {
        self.accentBorderColor = accentBorderColor
    }

    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppTheme.Colors.gunmetalGray)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accentBorderColor ?? AppTheme.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

/// Monospaced input field style with real-time validation border feedback.
public struct TacticalTextFieldModifier: ViewModifier {
    let isValid: Bool?

    public func body(content: Content) -> some View {
        content
            .font(AppTheme.Fonts.metricMono)
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.Colors.gunmetalElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        guard let isValid else { return AppTheme.Colors.borderSubtle }
        return isValid ? AppTheme.Colors.statusSuccess.opacity(0.85) : AppTheme.Colors.csOrange.opacity(0.85)
    }
}

/// Primary filled action button style (defaults to CS Orange).
public struct PrimaryActionButtonStyle: ButtonStyle {
    let tint: Color

    public init(tint: Color = AppTheme.Colors.csOrange) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.Colors.oledBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary outlined button style (defaults to CT Blue border).
public struct SecondaryActionButtonStyle: ButtonStyle {
    let borderColor: Color

    public init(borderColor: Color = AppTheme.Colors.ctBlue) {
        self.borderColor = borderColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.Colors.gunmetalElevated.opacity(configuration.isPressed ? 0.6 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

public extension View {
    func tacticalCard(accentBorder: Color? = nil) -> some View {
        modifier(TacticalCardModifier(accentBorderColor: accentBorder))
    }

    func tacticalTextField(isValid: Bool? = nil) -> some View {
        modifier(TacticalTextFieldModifier(isValid: isValid))
    }
}