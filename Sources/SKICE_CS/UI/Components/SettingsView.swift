import SwiftUI
import UIKit

/// Minimal Settings page containing the persistent Developer Debug Mode toggle.
/// When Developer Debug Mode is OFF, all diagnostic consoles and log actions remain completely hidden.
public struct SettingsView: View {
    @AppStorage("isDeveloperModeEnabled") private var isDeveloperModeEnabled: Bool = false
    @State private var logger = DebugLogger.shared
    @State private var didCopyLogs: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    developerModeToggleCard

                    if isDeveloperModeEnabled {
                        developerDiagnosticsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

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
                logStatBadge(
                    label: "INFO",
                    count: logger.entries.filter { $0.level == .info }.count,
                    color: AppTheme.Colors.ctBlue
                )
                logStatBadge(
                    label: "WARN",
                    count: logger.entries.filter { $0.level == .warning }.count,
                    color: AppTheme.Colors.csOrange
                )
                logStatBadge(
                    label: "ERROR",
                    count: logger.entries.filter { $0.level == .error }.count,
                    color: AppTheme.Colors.statusDanger
                )
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
}