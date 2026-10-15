import SwiftUI

/// Système de design centralisé inspiré de l'interface tactique de Counter-Strike 2 et optimisé pour dalles OLED.
public enum CSTheme {

    // MARK: - Palette de Couleurs

    public enum Colors {
        /// Noir pur (#000000) pour une extinction totale des pixels sur écran OLED.
        public static let oledBlack = Color(red: 0.0, green: 0.0, blue: 0.0)

        /// Surface secondaire carbone (#0D0F14) pour les conteneurs principaux.
        public static let surfacePrimary = Color(red: 0.051, green: 0.059, blue: 0.078)

        /// Surface élevée (#151922) pour les cartes interactives et champs de saisie.
        public static let surfaceElevated = Color(red: 0.082, green: 0.098, blue: 0.133)

        /// Bordure subtile (#252B3B) pour délimiter les blocs tactiques.
        public static let borderSubtle = Color(red: 0.145, green: 0.169, blue: 0.231)

        /// Orange CS2 / Terroriste (#E58E26) - Accent principal énergétique.
        public static let accentCSOrange = Color(red: 0.898, green: 0.557, blue: 0.149)

        /// Bleu Acier Anti-Terroriste (CT) (#4A78B5) - Accent secondaire tactique.
        public static let accentCTBlue = Color(red: 0.290, green: 0.471, blue: 0.710)

        /// Vert validation / VAC-Safe (#10B981).
        public static let statusSafe = Color(red: 0.063, green: 0.725, blue: 0.506)

        /// Rouge alerte / Erreur (#EF4444).
        public static let statusDanger = Color(red: 0.937, green: 0.267, blue: 0.267)

        /// Texte principal haute lisibilité (#F3F4F6).
        public static let textPrimary = Color(red: 0.953, green: 0.957, blue: 0.965)

        /// Texte secondaire technique (#9CA3AF).
        public static let textSecondary = Color(red: 0.612, green: 0.639, blue: 0.686)

        /// Dégradé signature CS2 (Orange T vers Bleu CT subtil).
        public static let tacticalHeaderGradient = LinearGradient(
            colors: [
                accentCSOrange.opacity(0.22),
                accentCTBlue.opacity(0.14),
                oledBlack
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typographies

    public enum Fonts {
        public static let headerTitle = Font.system(size: 22, weight: .black, design: .default)
        public static let sectionTitle = Font.system(size: 13, weight: .bold, design: .monospaced)
        public static let bodyRegular = Font.system(size: 15, weight: .medium, design: .default)
        public static let metricMono = Font.system(size: 14, weight: .semibold, design: .monospaced)
        public static let captionMono = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
}

// MARK: - Modificateurs de Vue Réutilisables

/// Style de carte tactique sombre avec bordure fine.
public struct CSTacticalCardModifier: ViewModifier {
    let accentBorderColor: Color?

    public init(accentBorderColor: Color? = nil) {
        self.accentBorderColor = accentBorderColor
    }

    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(CSTheme.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accentBorderColor ?? CSTheme.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

/// Style de champ de saisie monochrome adapté aux identifiants techniques (SteamID64 / API Key).
public struct CSTextFieldModifier: ViewModifier {
    let isValid: Bool?

    public func body(content: Content) -> some View {
        content
            .font(CSTheme.Fonts.metricMono)
            .foregroundStyle(CSTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(CSTheme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        guard let isValid else { return CSTheme.Colors.borderSubtle }
        return isValid ? CSTheme.Colors.statusSafe.opacity(0.8) : CSTheme.Colors.accentCSOrange.opacity(0.8)
    }
}

/// Style de bouton principal CS2 (Orange T ou Bleu CT).
public struct CSPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    public init(tint: Color = CSTheme.Colors.accentCSOrange) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(CSTheme.Colors.oledBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Style de bouton secondaire avec contour tactique.
public struct CSSecondaryButtonStyle: ButtonStyle {
    let borderColor: Color

    public init(borderColor: Color = CSTheme.Colors.accentCTBlue) {
        self.borderColor = borderColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(CSTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(CSTheme.Colors.surfaceElevated.opacity(configuration.isPressed ? 0.6 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

public extension View {
    func csTacticalCard(accentBorder: Color? = nil) -> some View {
        modifier(CSTacticalCardModifier(accentBorderColor: accentBorder))
    }

    func csTextFieldStyle(isValid: Bool? = nil) -> some View {
        modifier(CSTextFieldModifier(isValid: isValid))
    }
}