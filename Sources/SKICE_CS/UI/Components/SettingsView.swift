import SwiftUI
import UIKit

public struct SettingsView: View {
    let sessionStore: SteamSessionStore
    let statsModel: StatsViewModel
    let authSession: SteamAuthSession

    @AppStorage("isDeveloperModeEnabled") private var isDeveloperModeEnabled: Bool = false
    @State private var logger = DebugLogger.shared
    @State private var didCopyLogs: Bool = false

    // Steam
    @State private var steamIDInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var isShowingSteamAPIKeyPortal: Bool = false

    // FACEIT
    @State private var faceitIdentifierInput: String = ""
    @State private var faceitAPIKeyInput: String = ""
    @State private var faceitSaveMessage: String?
    @State private var isSavingFaceit: Bool = false

    private static let steamAPIKeyPortalURL = URL(string: "https://steamcommunity.com/dev/apikey")!

    public init(
        sessionStore: SteamSessionStore,
        statsModel: StatsViewModel,
        authSession: SteamAuthSession
    ) {
        self.sessionStore = sessionStore
        self.statsModel = statsModel
        self.authSession = authSession
    }

    private var isSteamIDValid: Bool? {
        guard !steamIDInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidSteamID64(steamIDInput)
    }

    private var isAPIKeyValid: Bool? {
        guard !apiKeyInput.isEmpty else { return nil }
        return SteamCredentialsValidator.isValidWebAPIKey(apiKeyInput)
    }

    private var isFaceitConfigured: Bool {
        !faceitAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    safetyHeader
                    connectionsSection
                    developerSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if let savedID = sessionStore.storedSteamID64 {
                steamIDInput = savedID
            }
            faceitIdentifierInput = AppCredentialsStore.readFaceitIdentifier()
            faceitAPIKeyInput = AppCredentialsStore.readFaceitAPIKey()
        }
        .sheet(isPresented: $isShowingSteamAPIKeyPortal) {
            SafariView(url: Self.steamAPIKeyPortalURL)
                .ignoresSafeArea()
        }
    }

    // MARK: - Safety header

    private var safetyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("ZERO-TRUST · LOCAL ONLY", systemImage: "lock.shield.fill")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.statusSuccess)

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.Colors.statusSuccess)
            }

            Text("Your data never leaves this device.")
                .font(AppTheme.Fonts.headerTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("SteamID64, API keys, and tokens are stored exclusively in the iOS Keychain. No intermediate server ever sees your credentials.")
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

    // MARK: - Connections

    private var connectionsSection: some View {
        VStack(spacing: 14) {
            sectionTitle("CONNECTIONS")
            steamCard
            SteamAuthCard(authSession: authSession)
            faceitCard
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.ctBlue)
            Spacer()
        }
    }

    private func connectionHeader(title: String, subtitle: String, icon: String, isConnected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isConnected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.csOrange)
                    .frame(width: 8, height: 8)
                Text(subtitle)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(isConnected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
            }
        }
    }

    private var steamCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionHeader(
                title: "STEAM",
                subtitle: sessionStore.storedSteamID64 != nil ? "Connected" : "Not connected",
                icon: "person.fill",
                isConnected: sessionStore.storedSteamID64 != nil
            )

            Divider().overlay(AppTheme.Colors.borderSubtle)

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
                    DebugLogger.shared.info("Saving credentials to Keychain for SteamID64: \(steamIDInput)", category: "Keychain")
                    sessionStore.saveCredentials(steamID64: steamIDInput, webAPIKey: apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("SAVE STEAM")
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
                            Text("CLEAR STEAM CREDENTIALS")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
                }
            }
            .padding(.top, 4)
        }
        .tacticalCard(
            accentBorder: sessionStore.storedSteamID64 != nil
                ? AppTheme.Colors.statusSuccess.opacity(0.4)
                : nil
        )
    }

    private var faceitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionHeader(
                title: "FACEIT",
                subtitle: isFaceitConfigured ? "Connected" : "Optional",
                icon: "flame.fill",
                isConnected: isFaceitConfigured
            )

            Divider().overlay(AppTheme.Colors.borderSubtle)

            VStack(alignment: .leading, spacing: 6) {
                Text("NICKNAME OR PLAYER ID")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                TextField("e.g. ZywOo", text: $faceitIdentifierInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tacticalTextField()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                SecureField("FACEIT v4 Client API Key", text: $faceitAPIKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tacticalTextField()
            }

            if let faceitSaveMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.statusSuccess)
                    Text(faceitSaveMessage)
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.statusSuccess)
                }
            }

            Button {
                Task { await saveFaceit() }
            } label: {
                HStack(spacing: 8) {
                    if isSavingFaceit {
                        ProgressView().tint(AppTheme.Colors.textPrimary)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text("SAVE FACEIT")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.ctBlue))
            .disabled(isSavingFaceit)
        }
        .tacticalCard(
            accentBorder: isFaceitConfigured ? AppTheme.Colors.ctBlue.opacity(0.4) : nil
        )
    }

    @MainActor
    private func saveFaceit() async {
        isSavingFaceit = true
        AppCredentialsStore.saveFaceitIdentifier(faceitIdentifierInput)
        AppCredentialsStore.saveFaceitAPIKey(faceitAPIKeyInput)
        await statsModel.refreshStats(explicitSteamID64: sessionStore.storedSteamID64)
        isSavingFaceit = false
        faceitSaveMessage = faceitAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "FACEIT removed."
            : "FACEIT saved & synced."
        try? await Task.sleep(for: .seconds(2))
        faceitSaveMessage = nil
    }

    // MARK: - Developer

    private var developerSection: some View {
        VStack(spacing: 14) {
            sectionTitle("DEVELOPER")

            developerModeToggleCard

            if isDeveloperModeEnabled {
                developerDiagnosticsCard
            }
        }
    }

    private var developerModeToggleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DEVELOPER OPTIONS", systemImage: "wrench.and.screwdriver.fill")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.csOrange)
                Spacer()
                Text(isDeveloperModeEnabled ? "ACTIVE" : "DISABLED")
                    .font(AppTheme.Fonts.captionMono)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (isDeveloperModeEnabled ? AppTheme.Colors.statusSuccess : Color.white)
                            .opacity(0.14)
                    )
                    .foregroundStyle(isDeveloperModeEnabled ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
                    .clipShape(Capsule())
            }

            Divider()
                .overlay(AppTheme.Colors.borderSubtle)

            Toggle(isOn: $isDeveloperModeEnabled.animation(.snappy(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Developer Debug Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text("Exposes in-app HTTP request/response logs, status codes, raw payload inspection, and toolbar debug shortcuts.")
                        .font(AppTheme.Fonts.bodyRegular)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .tint(AppTheme.Colors.csOrange)
        }
        .tacticalCard(
            accentBorder: isDeveloperModeEnabled ? AppTheme.Colors.csOrange.opacity(0.45) : nil
        )
    }

    private var developerDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("DIAGNOSTIC CONSOLE & LOGS", systemImage: "terminal.fill")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.ctBlue)

                Spacer()

                Text("\(logger.entries.count)/\(DebugLogger.maxEntries)")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Divider()
                .overlay(AppTheme.Colors.borderSubtle)

            HStack(spacing: 14) {
                logStatBadge(label: "INFO", count: logger.entries.filter { $0.level == .info }.count, color: AppTheme.Colors.ctBlue)
                logStatBadge(label: "WARN", count: logger.entries.filter { $0.level == .warning }.count, color: AppTheme.Colors.csOrange)
                logStatBadge(label: "ERROR", count: logger.entries.filter { $0.level == .error }.count, color: AppTheme.Colors.statusDanger)
                Spacer()
            }

            NavigationLink {
                DebugLogsView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                    Text("OPEN FULL DEBUG CONSOLE")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Colors.ctBlue.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Colors.ctBlue.opacity(0.5), lineWidth: 1)
                )
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = logger.exportFormattedLogs()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didCopyLogs = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            didCopyLogs = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didCopyLogs ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        Text(didCopyLogs ? "COPIED TO CLIPBOARD" : "COPY LOGS")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.ctBlue))
                .disabled(logger.entries.isEmpty)

                Button {
                    logger.clear()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("CLEAR")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
                .disabled(logger.entries.isEmpty)
            }
        }
        .tacticalCard(accentBorder: AppTheme.Colors.ctBlue.opacity(0.45))
    }

    private func logStatBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label): \(count)")
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("ABOUT")

            HStack {
                Text("Version")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text("1.0.0")
                    .font(AppTheme.Fonts.metricMono)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Divider().overlay(AppTheme.Colors.borderSubtle)

            Text("SKICE_CS is open source and zero-trust. Your credentials never leave this device.")
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Button {
                statsModel.clearStatsCache()
            } label: {
                Label("Clear Cached Stats & Snapshots", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
        }
        .tacticalCard()
    }
}
