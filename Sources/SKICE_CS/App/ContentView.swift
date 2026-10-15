import SwiftUI

public struct ContentView: View {
    @State private var sessionStore = SteamSessionStore()
    @State private var steamIDInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var isAPIKeyVisible: Bool = false

    public init() {}

    private var isSteamIDValid: Bool? {
        guard !steamIDInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidSteamID64(steamIDInput)
    }

    private var isAPIKeyValid: Bool? {
        guard !apiKeyInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidSteamAPIKey(apiKeyInput)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CSTheme.Colors.oledBlack
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerBanner
                        securityStatusCard
                        profileSummaryCard
                        credentialsFormCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("SKICE // CS2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(CSTheme.Colors.oledBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if let savedID = sessionStore.storedSteamID64 {
                    steamIDInput = savedID
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sous-vues

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PHASE 1 : SOCLE & KEYCHAIN", systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(CSTheme.Fonts.captionMono)
                    .foregroundStyle(CSTheme.Colors.accentCSOrange)

                Spacer()

                Text("ZERO-TRUST")
                    .font(CSTheme.Fonts.captionMono)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CSTheme.Colors.statusSafe.opacity(0.15))
                    .foregroundStyle(CSTheme.Colors.statusSafe)
                    .clipShape(Capsule())
            }

            Text("AUTHENTIFICATION LOCALE STEAM")
                .font(CSTheme.Fonts.headerTitle)
                .foregroundStyle(CSTheme.Colors.textPrimary)

            Text("Vos clés et identifiants sont stockés exclusivement dans le trousseau matériel iOS. Aucune donnée ne transite par un serveur tiers.")
                .font(CSTheme.Fonts.bodyRegular)
                .foregroundStyle(CSTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CSTheme.Colors.tacticalHeaderGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CSTheme.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private var securityStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ÉTAT DU TROUSSEAU KEYCHAIN")
                    .font(CSTheme.Fonts.sectionTitle)
                    .foregroundStyle(CSTheme.Colors.accentCTBlue)
                Spacer()
                Circle()
                    .fill(sessionStore.storedSteamID64 != nil ? CSTheme.Colors.statusSafe : CSTheme.Colors.accentCSOrange)
                    .frame(width: 9, height: 9)
            }

            Divider()
                .overlay(CSTheme.Colors.borderSubtle)

            HStack {
                Text("SteamID64 stocké :")
                    .font(CSTheme.Fonts.bodyRegular)
                    .foregroundStyle(CSTheme.Colors.textSecondary)
                Spacer()
                Text(sessionStore.storedSteamID64 ?? "NON CONFIGURÉ")
                    .font(CSTheme.Fonts.metricMono)
                    .foregroundStyle(
                        sessionStore.storedSteamID64 != nil
                            ? CSTheme.Colors.statusSafe
                            : CSTheme.Colors.textSecondary
                    )
            }

            HStack {
                Text("Clé Steam Web API :")
                    .font(CSTheme.Fonts.bodyRegular)
                    .foregroundStyle(CSTheme.Colors.textSecondary)
                Spacer()
                Text(sessionStore.maskedAPIKey ?? "AUCUNE CLÉ")
                    .font(CSTheme.Fonts.captionMono)
                    .foregroundStyle(
                        sessionStore.hasStoredAPIKey
                            ? CSTheme.Colors.accentCSOrange
                            : CSTheme.Colors.textSecondary
                    )
            }
        }
        .csTacticalCard(
            accentBorder: sessionStore.storedSteamID64 != nil
                ? CSTheme.Colors.statusSafe.opacity(0.45)
                : nil
        )
    }

    @ViewBuilder
    private var profileSummaryCard: some View {
        if let profile = sessionStore.activeProfile {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CSTheme.Colors.surfaceElevated)
                            .frame(width: 54, height: 54)

                        if let avatarURL = profile.avatarFullURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Image(systemName: "person.crop.square.fill")
                                        .font(.title2)
                                        .foregroundStyle(CSTheme.Colors.accentCSOrange)
                                }
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "person.crop.square.fill")
                                .font(.title2)
                                .foregroundStyle(CSTheme.Colors.accentCSOrange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.personaName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(CSTheme.Colors.textPrimary)

                            if profile.isPlayingCS2 {
                                Text("CS2 ACTIF")
                                    .font(CSTheme.Fonts.captionMono)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(CSTheme.Colors.accentCSOrange.opacity(0.2))
                                    .foregroundStyle(CSTheme.Colors.accentCSOrange)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("ID : \(profile.steamID64)")
                            .font(CSTheme.Fonts.captionMono)
                            .foregroundStyle(CSTheme.Colors.textSecondary)

                        HStack(spacing: 10) {
                            Label(profile.personaState.label, systemImage: "dot.radiowaves.left.and.right")
                                .font(CSTheme.Fonts.captionMono)
                                .foregroundStyle(CSTheme.Colors.accentCTBlue)

                            Label(profile.visibilityState.label, systemImage: "eye")
                                .font(CSTheme.Fonts.captionMono)
                                .foregroundStyle(CSTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()
                }

                if sessionStore.hasStoredAPIKey {
                    Button {
                        Task {
                            await sessionStore.syncProfileFromSteamWebAPI()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if sessionStore.isLoadingNetwork {
                                ProgressView()
                                    .tint(CSTheme.Colors.textPrimary)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("TESTER L'APPEL DIRECT-TO-API STEAM")
                        }
                    }
                    .buttonStyle(CSSecondaryButtonStyle(borderColor: CSTheme.Colors.accentCTBlue))
                    .disabled(sessionStore.isLoadingNetwork)
                }
            }
            .csTacticalCard(accentBorder: CSTheme.Colors.accentCTBlue.opacity(0.5))
        }
    }

    private var credentialsFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONFIGURATION DES ACCÈS STEAM")
                .font(CSTheme.Fonts.sectionTitle)
                .foregroundStyle(CSTheme.Colors.accentCSOrange)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STEAMID64 (17 CHIFFRES)")
                        .font(CSTheme.Fonts.captionMono)
                        .foregroundStyle(CSTheme.Colors.textSecondary)
                    Spacer()
                    if let isSteamIDValid {
                        Text(isSteamIDValid ? "FORMAT VALIDE" : "FORMAT INVALIDE")
                            .font(CSTheme.Fonts.captionMono)
                            .foregroundStyle(isSteamIDValid ? CSTheme.Colors.statusSafe : CSTheme.Colors.accentCSOrange)
                    }
                }

                TextField("76561198000000000", text: $steamIDInput)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .csTextFieldStyle(isValid: isSteamIDValid)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CLÉ STEAM WEB API (OPTIONNELLE - 32 HEX)")
                        .font(CSTheme.Fonts.captionMono)
                        .foregroundStyle(CSTheme.Colors.textSecondary)
                    Spacer()
                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Text(isAPIKeyVisible ? "MASQUER" : "AFFICHER")
                            .font(CSTheme.Fonts.captionMono)
                            .foregroundStyle(CSTheme.Colors.accentCTBlue)
                    }
                }

                Group {
                    if isAPIKeyVisible {
                        TextField("Ex: A1B2C3D4E5F60718293A4B5C6D7E8F90", text: $apiKeyInput)
                    } else {
                        SecureField("Clé locale stockée dans le Keychain", text: $apiKeyInput)
                    }
                }
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .csTextFieldStyle(isValid: isAPIKeyValid)
            }

            if let statusMessage = sessionStore.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(CSTheme.Colors.statusSafe)
                    Text(statusMessage)
                        .font(CSTheme.Fonts.captionMono)
                        .foregroundStyle(CSTheme.Colors.statusSafe)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CSTheme.Colors.statusSafe.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let errorMessage = sessionStore.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(CSTheme.Colors.statusDanger)
                    Text(errorMessage)
                        .font(CSTheme.Fonts.captionMono)
                        .foregroundStyle(CSTheme.Colors.statusDanger)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CSTheme.Colors.statusDanger.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(spacing: 10) {
                Button {
                    sessionStore.saveCredentials(steamID64: steamIDInput, apiKey: apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("ENREGISTRER DANS LE KEYCHAIN")
                    }
                }
                .buttonStyle(CSPrimaryButtonStyle(tint: CSTheme.Colors.accentCSOrange))

                if sessionStore.storedSteamID64 != nil || sessionStore.hasStoredAPIKey {
                    Button {
                        sessionStore.purgeCredentials()
                        steamIDInput = ""
                        apiKeyInput = ""
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                            Text("PURGER LE TROUSSEAU LOCAL")
                        }
                    }
                    .buttonStyle(CSSecondaryButtonStyle(borderColor: CSTheme.Colors.statusDanger))
                }
            }
            .padding(.top, 4)
        }
        .csTacticalCard()
    }
}