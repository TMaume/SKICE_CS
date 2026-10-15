import SwiftUI

/// Tier B entry point in Settings: sign in to a real Steam session (token pair
/// plus Steam Guard), inspect the stored session, sign out.
///
/// Nothing here leaves the device except direct requests to Steam, and the
/// tokens themselves are written to the Keychain by SteamAuthSession.
public struct SteamAuthCard: View {
    let authSession: SteamAuthSession

    @State private var accountNameInput: String = ""
    @State private var passwordInput: String = ""
    @State private var guardCodeInput: String = ""
    @State private var isPasswordVisible: Bool = false

    public init(authSession: SteamAuthSession) {
        self.authSession = authSession
    }

    private var isSignedIn: Bool { authSession.state == .signedIn }
    private var isConnected: Bool { authSession.hasPersistedRefreshToken }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().overlay(AppTheme.Colors.borderSubtle)
            stateSection
            if let status = authSession.statusMessage, !status.isEmpty {
                statusBanner(text: status, isError: false)
            }
            if let error = authSession.errorMessage, !error.isEmpty {
                statusBanner(text: error, isError: true)
            }
        }
        .tacticalCard(accentBorder: isConnected ? AppTheme.Colors.statusSuccess.opacity(0.4) : nil)
        .onAppear {
            if accountNameInput.isEmpty, let stored = authSession.accountName {
                accountNameInput = stored
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.key.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isConnected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("STEAM SESSION")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Tier B · Game Coordinator access")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(authSession.stateSummary)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(stateColor)
            }
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch authSession.state {
        case .signedIn:
            signedInSection
        case .authenticating:
            busySection(label: "Contacting Steam…")
        case .awaitingRemoteApproval:
            remoteApprovalSection
        case .awaitingGuardCode:
            guardCodeSection
        case .signedOut, .expired, .failed:
            signedOutSection
        }
    }

    private var signedInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(
                label: "ACCOUNT",
                value: authSession.accountName ?? "unknown"
            )
            infoRow(
                label: "STEAMID64",
                value: authSession.sessionSteamID64 ?? "unknown"
            )
            infoRow(
                label: "ACCESS TOKEN",
                value: authSession.accessTokenExpiry.map { "expires " + Self.expiryFormatter.string(from: $0) } ?? "expiry unknown"
            )
            infoRow(
                label: "REFRESH TOKEN",
                value: authSession.hasPersistedRefreshToken ? "stored in Keychain" : "not issued"
            )

            HStack(spacing: 10) {
                Button {
                    Task { await authSession.ensureFreshAccessToken() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("REFRESH TOKEN")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.ctBlue))
                .disabled(authSession.isBusy)

                Button {
                    authSession.signOut()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("SIGN OUT")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
            }
        }
    }

    private var signedOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signing in here creates a real Steam session on this device. Steam Guard is handled inside the app; tokens are written to the Keychain and sent only to Steam.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("STEAM ACCOUNT NAME")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                TextField("account name", text: $accountNameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tacticalTextField()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PASSWORD")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Text(isPasswordVisible ? "HIDE" : "SHOW")
                            .font(AppTheme.Fonts.captionMono)
                            .foregroundStyle(AppTheme.Colors.ctBlue)
                    }
                }

                Group {
                    if isPasswordVisible {
                        TextField("Steam password", text: $passwordInput)
                    } else {
                        SecureField("Steam password", text: $passwordInput)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tacticalTextField()
            }

            if authSession.state == .expired, authSession.hasPersistedRefreshToken {
                Button {
                    Task { await authSession.ensureFreshAccessToken() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("RECOVER STORED SESSION")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.ctBlue))
            }

            Button {
                Task {
                    await authSession.signIn(accountName: accountNameInput, password: passwordInput)
                    passwordInput = ""
                }
            } label: {
                HStack(spacing: 8) {
                    if authSession.isBusy {
                        ProgressView().tint(AppTheme.Colors.textPrimary)
                    } else {
                        Image(systemName: "lock.open.fill")
                    }
                    Text("SIGN IN TO STEAM")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))
            .disabled(authSession.isBusy)
        }
    }

    private var guardCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steam sent a Steam Guard code to your email. Enter it to finish signing in.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("STEAM GUARD CODE")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                TextField("ABCDE", text: $guardCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .tacticalTextField()
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await authSession.submitGuardCode(guardCodeInput)
                        guardCodeInput = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        if authSession.isBusy {
                            ProgressView().tint(AppTheme.Colors.textPrimary)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                        }
                        Text("SUBMIT CODE")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))
                .disabled(authSession.isBusy)

                Button {
                    authSession.cancelPendingSignIn()
                } label: {
                    Text("CANCEL")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
            }
        }
    }

    private var remoteApprovalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            busySection(label: "Waiting for approval in the Steam mobile app…")

            Button {
                authSession.cancelPendingSignIn()
            } label: {
                Text("CANCEL")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
        }
    }

    private func busySection(label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(AppTheme.Colors.ctBlue)
            Text(label)
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusBanner(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .foregroundStyle(isError ? AppTheme.Colors.statusDanger : AppTheme.Colors.statusSuccess)
            Text(text)
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(isError ? AppTheme.Colors.statusDanger : AppTheme.Colors.statusSuccess)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? AppTheme.Colors.statusDanger : AppTheme.Colors.statusSuccess).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var stateColor: Color {
        switch authSession.state {
        case .signedIn: return AppTheme.Colors.statusSuccess
        case .failed, .expired: return AppTheme.Colors.statusDanger
        case .signedOut: return AppTheme.Colors.textSecondary
        default: return AppTheme.Colors.csOrange
        }
    }
}
