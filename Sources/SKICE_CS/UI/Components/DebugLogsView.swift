import SwiftUI
import UIKit

/// Minimal in-app diagnostic console for inspecting HTTP requests, status codes, and raw payloads on physical devices.
public struct DebugLogsView: View {
    @State private var logger = DebugLogger.shared
    @State private var selectedLevelFilter: DebugLogLevel? = nil
    @State private var didCopyConfirmation: Bool = false

    public init() {}

    private var filteredEntries: [DebugLogEntry] {
        guard let filter = selectedLevelFilter else {
            return logger.entries
        }
        return logger.entries.filter { $0.level == filter }
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                consoleToolbar
                Divider()
                    .overlay(AppTheme.Colors.borderSubtle)

                if filteredEntries.isEmpty {
                    emptyConsoleView
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredEntries) { entry in
                                DebugLogRow(entry: entry)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .navigationTitle("DEBUG CONSOLE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var consoleToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("\(logger.entries.count)/\(DebugLogger.maxEntries) LOGS", systemImage: "terminal.fill")
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.ctBlue)

                Spacer()

                Button {
                    UIPasteboard.general.string = logger.exportFormattedLogs()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didCopyConfirmation = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            didCopyConfirmation = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: didCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        Text(didCopyConfirmation ? "COPIED" : "COPY LOGS")
                    }
                    .font(AppTheme.Fonts.captionMono)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(didCopyConfirmation ? AppTheme.Colors.statusSuccess.opacity(0.2) : AppTheme.Colors.gunmetalElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(didCopyConfirmation ? AppTheme.Colors.statusSuccess : AppTheme.Colors.ctBlue.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundStyle(didCopyConfirmation ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textPrimary)
                }
                .disabled(logger.entries.isEmpty)

                Button {
                    logger.clear()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                        Text("CLEAR")
                    }
                    .font(AppTheme.Fonts.captionMono)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppTheme.Colors.statusDanger.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AppTheme.Colors.statusDanger.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundStyle(AppTheme.Colors.statusDanger)
                }
                .disabled(logger.entries.isEmpty)
            }

            // Level Filter Pills
            HStack(spacing: 8) {
                levelFilterChip(title: "ALL", level: nil)
                ForEach(DebugLogLevel.allCases, id: \.self) { level in
                    levelFilterChip(title: level.rawValue, level: level)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.06))
    }

    private func levelFilterChip(title: String, level: DebugLogLevel?) -> some View {
        let isSelected = selectedLevelFilter == level
        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                selectedLevelFilter = level
            }
        } label: {
            Text(title)
                .font(AppTheme.Fonts.captionMono)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.Colors.csOrange : Color(white: 0.14))
                )
                .foregroundStyle(isSelected ? Color.black : AppTheme.Colors.textSecondary)
        }
    }

    private var emptyConsoleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("NO DIAGNOSTIC LOGS RECORDED")
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Trigger an inventory refresh or network call to inspect URLs, headers, status codes, and raw payloads.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Individual Log Row

private struct DebugLogRow: View {
    let entry: DebugLogEntry
    @State private var isExpanded: Bool = true

    private var levelColor: Color {
        switch entry.level {
        case .info:
            return AppTheme.Colors.ctBlue
        case .warning:
            return AppTheme.Colors.csOrange
        case .error:
            return AppTheme.Colors.statusDanger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.formattedTimestamp)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(entry.level.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.2))
                    .foregroundStyle(levelColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(entry.category.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if let status = entry.httpStatusCode {
                    Text("HTTP \(status)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (status == 200 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.statusDanger)
                                .opacity(0.2)
                        )
                        .foregroundStyle(status == 200 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.statusDanger)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                if entry.rawPayload != nil {
                    Button {
                        withAnimation(.snappy(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }

            Text(entry.message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .textSelection(.enabled)

            if isExpanded, let payload = entry.rawPayload, !payload.isEmpty {
                Text(payload)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(levelColor.opacity(0.9))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(levelColor.opacity(0.35), lineWidth: 1)
                )
        )
    }
}