import SwiftUI

public struct ContentView: View {
    public enum AppTab: Hashable {
        case profile
        case inventory
        case stats
        case settings
    }

    @State private var selectedTab: AppTab = .profile
    @State private var sessionStore = SteamSessionStore()
    @State private var steamIDInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var isShowingSteamAPIKeyPortal: Bool = false

    private static let steamAPIKeyPortalURL = URL(string: "https://steamcommunity.com/dev/apikey")!

    public init() {}

    private var isSteamIDValid: Bool? {
        guard !steamIDInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidSteamID64(steamIDInput)
    }

    private var isAPIKeyValid: Bool? {
        guard !apiKeyInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidWebAPIKey(apiKeyInput)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1: Profile & Keychain Setup
            NavigationStack {
                ZStack {
                    AppTheme.Colors.oledBlack
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 18) {
                            headerBanner
                            keychainStatusCard
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
                .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .onAppear {
                    if let savedID = sessionStore.storedSteamID64 {
                        steamIDInput = savedID
                    }
                }
                .sheet(isPresented: $isShowingSteamAPIKeyPortal) {
                    SafariView(url: Self.steamAPIKeyPortalURL)
                        .ignoresSafeArea()
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.badge.key.fill")
            }
            .tag(AppTab.profile)

            // TAB 2: CS2 Inventory
            NavigationStack {
                if let steamID64 = sessionStore.storedSteamID64, !steamID64.isEmpty {
                    InventoryView(steamID64: steamID64)
                } else {
                    missingSteamIDPlaceholder
                }
            }
            .tabItem {
                Label("Inventory", systemImage: "shippingbox.fill")
            }
            .tag(AppTab.inventory)

            // TAB 3: CS2 & FACEIT Stats Dashboard (Module 4)
            NavigationStack {
                StatsDashboardView(steamID64: sessionStore.storedSteamID64)
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.doc.horizontal.fill")
            }
            .tag(AppTab.stats)

            // TAB 4: Minimal Settings (Hides Debug Tools unless Developer Mode is ON)
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(AppTheme.Colors.csOrange)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var missingSteamIDPlaceholder: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.Colors.csOrange)

                Text("STEAMID64 NOT CONFIGURED")
                    .font(AppTheme.Fonts.headerTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Please save your 17-digit SteamID64 in the Profile tab to fetch your public CS2 inventory.")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    selectedTab = .profile
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.circle.fill")
                        Text("CONFIGURE STEAMID64")
                    }
                    .padding(.horizontal, 20)
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))
                .frame(maxWidth: 260)
            }
        }
        .navigationTitle("CS2 Inventory")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PHASE 1 : CORE & KEYCHAIN", systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.csOrange)

                Spacer()

                Text("ZERO-TRUST")
                    .font(AppTheme.Fonts.captionMono)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.Colors.statusSuccess.opacity(0.15))
                    .foregroundStyle(AppTheme.Colors.statusSuccess)
                    .clipShape(Capsule())
            }

            Text("LOCAL STEAM AUTHENTICATION")
                .font(AppTheme.Fonts.headerTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Your SteamID64 and optional Web API Key are stored exclusively in the iOS hardware Keychain. No intermediate server ever accesses your credentials.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.Colors.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private var keychainStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KEYCHAIN VAULT STATUS")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.ctBlue)
                Spacer()
                Circle()
                    .fill(sessionStore.storedSteamID64 != nil ? AppTheme.Colors.statusSuccess : AppTheme.Colors.csOrange)
                    .frame(width: 9, height: 9)
            }

            Divider()
                .overlay(AppTheme.Colors.borderSubtle)

            HStack {
                Text("Stored SteamID64:")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(sessionStore.storedSteamID64 ?? "NOT CONFIGURED")
                    .font(AppTheme.Fonts.metricMono)
                    .foregroundStyle(
                        sessionStore.storedSteamID64 != nil
                            ? AppTheme.Colors.statusSuccess
                            : AppTheme.Colors.textSecondary
                    )
            }

            HStack {
                Text("Steam Web API Key:")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(sessionStore.maskedAPIKey ?? "PUBLIC ENDPOINTS ONLY")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(
                        sessionStore.hasStoredAPIKey
                            ? AppTheme.Colors.csOrange
                            : AppTheme.Colors.textSecondary
                    )
            }
        }
        .tacticalCard(
            accentBorder: sessionStore.storedSteamID64 != nil
                ? AppTheme.Colors.statusSuccess.opacity(0.45)
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
                            .fill(AppTheme.Colors.gunmetalElevated)
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
                                        .foregroundStyle(AppTheme.Colors.csOrange)
                                }
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "person.crop.square.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.Colors.csOrange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.personaName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)

                            if profile.isPlayingCS2 {
                                Text("IN CS2")
                                    .font(AppTheme.Fonts.captionMono)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.Colors.csOrange.opacity(0.2))
                                    .foregroundStyle(AppTheme.Colors.csOrange)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("ID: \(profile.steamID64)")
                            .font(AppTheme.Fonts.captionMono)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        HStack(spacing: 10) {
                            Label(profile.personaState.displayName, systemImage: "dot.radiowaves.left.and.right")
                                .font(AppTheme.Fonts.captionMono)
                                .foregroundStyle(AppTheme.Colors.ctBlue)

                            Label(profile.visibilityState.displayName, systemImage: "eye")
                                .font(AppTheme.Fonts.captionMono)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    if sessionStore.hasStoredAPIKey {
                        Button {
                            Task {
                                await sessionStore.syncProfileFromSteamWebAPI()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if sessionStore.isLoadingNetwork {
                                    ProgressView()
                                        .tint(AppTheme.Colors.textPrimary)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("SYNC PROFILE")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.ctBlue))
                        .disabled(sessionStore.isLoadingNetwork)
                    }

                    Button {
                        selectedTab = .inventory
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                            Text("OPEN INVENTORY")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.csOrange))
                }
            }
            .tacticalCard(accentBorder: AppTheme.Colors.ctBlue.opacity(0.5))
        }
    }

    private var credentialsFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STEAM CREDENTIALS SETUP")
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.csOrange)

            // SteamID64 Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STEAMID64 (17 DIGITS)")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    if let isSteamIDValid {
                        Text(isSteamIDValid ? "VALID FORMAT" : "INVALID FORMAT")
                            .font(AppTheme.Fonts.captionMono)
                            .foregroundStyle(isSteamIDValid ? AppTheme.Colors.statusSuccess : AppTheme.Colors.csOrange)
                    }
                }

                TextField("76561198000000000", text: $steamIDInput)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tacticalTextField(isValid: isSteamIDValid)
            }

            // Steam Web API Key Field + "Get API Key" Button
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("STEAM WEB API KEY (OPTIONAL)")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Text(isAPIKeyVisible ? "HIDE" : "SHOW")
                            .font(AppTheme.Fonts.captionMono)
                            .foregroundStyle(AppTheme.Colors.ctBlue)
                    }
                }

                HStack(spacing: 8) {
                    Group {
                        if isAPIKeyVisible {
                            TextField("32-character hex key", text: $apiKeyInput)
                        } else {
                            SecureField("Stored locally in Keychain", text: $apiKeyInput)
                        }
                    }
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .tacticalTextField(isValid: isAPIKeyValid)

                    Button {
                        isShowingSteamAPIKeyPortal = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "key.fill")
                            Text("Get API Key")
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.csOrange))
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.Colors.ctBlue)
                        .font(.system(size: 15))
                        .padding(.top, 1)

                    Text("When prompted on Steam, you can enter 'localhost' in the Domain Name field.")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.ctBlue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.Colors.ctBlue.opacity(0.35), lineWidth: 1)
                )
            }

            if let statusMessage = sessionStore.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(AppTheme.Colors.statusSuccess)
                    Text(statusMessage)
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.statusSuccess)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.statusSuccess.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let errorMessage = sessionStore.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.Colors.statusDanger)
                    Text(errorMessage)
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.statusDanger)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.statusDanger.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(spacing: 10) {
                Button {
                    DebugLogger.shared.info(
                        "Saving credentials to Keychain for SteamID64: \(steamIDInput)",
                        category: "Keychain"
                    )
                    sessionStore.saveCredentials(steamID64: steamIDInput, webAPIKey: apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("SAVE TO KEYCHAIN")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))

                if sessionStore.storedSteamID64 != nil || sessionStore.hasStoredAPIKey {
                    Button {
                        DebugLogger.shared.warning("Cleared stored credentials from Keychain.", category: "Keychain")
                        sessionStore.clearCredentials()
                        steamIDInput = ""
                        apiKeyInput = ""
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                            Text("CLEAR KEYCHAIN CREDENTIALS")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
                }
            }
            .padding(.top, 4)
        }
        .tacticalCard()
    }
}