import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Renders a QR code image for a given string payload.
private func makeQRImage(from string: String) -> UIImage? {
    guard !string.isEmpty else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scale: CGFloat = 12
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}

/// Tier 3 entry point in Settings: sign in to a real Steam session by scanning
/// a QR code with the Steam mobile app. No password is handled on-device, and
/// the resulting tokens live in the Keychain.
public struct SteamAuthCard: View {
    let authSession: SteamAuthSession

    @State private var guardCodeInput: String = ""

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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            tierBadge("3")
            Image(systemName: "person.badge.key.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isConnected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("STEAM GC")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Tier 3 · Game Coordinator access")
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

    // MARK: - State

    @ViewBuilder
    private var stateSection: some View {
        switch authSession.state {
        case .signedIn:
            signedInSection
        case .authenticating:
            busySection(label: "Contacting Steam…")
        case .awaitingRemoteApproval:
            qrApprovalSection
        case .awaitingGuardCode:
            guardCodeSection
        case .signedOut, .expired, .failed:
            qrSignInSection
        }
    }

    private var signedInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(label: "ACCOUNT", value: authSession.accountName ?? "unknown")
            infoRow(label: "STEAMID64", value: authSession.sessionSteamID64 ?? "unknown")
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

    private var qrSignInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in by scanning a QR code with the Steam mobile app. Your Steam password is never typed into this app.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
                Task { await authSession.signInViaQR() }
            } label: {
                HStack(spacing: 8) {
                    if authSession.isBusy {
                        ProgressView().tint(AppTheme.Colors.textPrimary)
                    } else {
                        Image(systemName: "qrcode")
                    }
                    Text("SIGN IN WITH STEAM APP")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.Colors.csOrange))
            .disabled(authSession.isBusy)
        }
    }

    private var qrApprovalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let url = authSession.pendingQRURL {
                if let qrImage = makeQRImage(from: url) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: .infinity)
                }

                Text("Open the Steam mobile app → Steam Guard → tap the QR icon → scan this code, then approve the sign-in.")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                busySection(label: "Preparing the QR code…")
            }

            HStack(spacing: 10) {
                ProgressView().tint(AppTheme.Colors.ctBlue)
                Text("Waiting for approval…")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
            }

            Button {
                authSession.cancelPendingSignIn()
            } label: {
                Text("CANCEL")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.statusDanger))
        }
    }

    private var guardCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steam sent a Steam Guard code. Enter it to finish signing in.")
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

    // MARK: - Pieces

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

    private func tierBadge(_ number: String) -> some View {
        Text(number)
            .font(AppTheme.Fonts.captionMono)
            .foregroundStyle(AppTheme.Colors.ctBlue)
            .frame(width: 22, height: 22)
            .background(Circle().fill(AppTheme.Colors.ctBlue.opacity(0.15)))
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
