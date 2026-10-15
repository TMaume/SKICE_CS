import SwiftUI

/// Home dashboard: your Steam identity, connection status, a career snapshot,
/// FACEIT badge, and a shortcut into your inventory. Read-only; configuration
/// lives in Settings.
public struct ProfileView: View {
    let sessionStore: SteamSessionStore
    let statsModel: StatsViewModel
    @Binding var selectedTab: AppTab

    public init(sessionStore: SteamSessionStore, statsModel: StatsViewModel, selectedTab: Binding<AppTab>) {
        self.sessionStore = sessionStore
        self.statsModel = statsModel
        self._selectedTab = selectedTab
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    connectionStatusCard

                    if let stats = statsModel.overviewStats {
                        careerSnapshot(stats)
                        if stats.faceitStats != nil {
                            faceitBadge(stats)
                        }
                    } else if statsModel.isLoading {
                        loadingCard
                    } else {
                        emptyStatsCard
                    }

                    inventoryTile
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await statsModel.refreshStats(explicitSteamID64: sessionStore.storedSteamID64)
        }
        .task(id: sessionStore.storedSteamID64) {
            await statsModel.loadStatsIfNeeded(explicitSteamID64: sessionStore.storedSteamID64)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var identityCard: some View {
        if let profile = sessionStore.activeProfile {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.Colors.gunmetalElevated)
                        .frame(width: 56, height: 56)

                    if let avatarURL = profile.avatarFullURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Image(systemName: "person.crop.square.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.Colors.csOrange)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "person.crop.square.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.Colors.csOrange)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.personaName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

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

                    if let errorMessage = sessionStore.errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.Fonts.captionMono)
                            .foregroundStyle(AppTheme.Colors.statusDanger)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button {
                    Task { await sessionStore.syncProfileFromSteamWebAPI() }
                } label: {
                    if sessionStore.isLoadingNetwork {
                        ProgressView()
                            .tint(AppTheme.Colors.csOrange)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.csOrange)
                    }
                }
                .disabled(sessionStore.isLoadingNetwork)
                .accessibilityLabel("Sync Steam Profile")
            }
            .tacticalCard(accentBorder: AppTheme.Colors.ctBlue.opacity(0.4))
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.Colors.csOrange)
                Text("No Steam account connected")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Connect your SteamID64 in Settings to see your profile.")
                    .font(AppTheme.Fonts.bodyRegular)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .tacticalCard()
        }
    }

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CONNECTIONS")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.ctBlue)
                Spacer()
                Button {
                    selectedTab = .settings
                } label: {
                    HStack(spacing: 4) {
                        Text("MANAGE")
                        Image(systemName: "chevron.right")
                    }
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.csOrange)
                }
            }

            HStack(spacing: 12) {
                connectionChip(title: "Steam", connected: sessionStore.storedSteamID64 != nil)
                connectionChip(title: "FACEIT", connected: !AppCredentialsStore.readFaceitAPIKey().isEmpty)
            }
        }
        .tacticalCard()
    }

    private func connectionChip(title: String, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(title)
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(connected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
            Spacer()
            Text(connected ? "ON" : "OFF")
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(connected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.gunmetalElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func careerSnapshot(_ stats: PlayerOverviewStats) -> some View {
        let kd = stats.kdRatio(for: .combined, activeSteam: statsModel.activeSteamStats)
        let winRate = stats.winRatePercentage(
            for: .combined,
            faction: .both,
            activeSteam: statsModel.activeSteamStats,
            filteredFaceitMatches: statsModel.filteredFaceitMatches
        )
        let hs = stats.headshotPercentage(for: .combined, activeSteam: statsModel.activeSteamStats)
        let hours = statsModel.activeSteamStats?.timePlayedHours ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CAREER SNAPSHOT")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.csOrange)
                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                metricTile(label: "K/D", value: String(format: "%.2f", kd), accent: kd >= 1.0 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.csOrange)
                metricTile(label: "WIN RATE", value: String(format: "%.1f%%", winRate), accent: winRate >= 50.0 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.ctBlue)
                metricTile(label: "HEADSHOT", value: String(format: "%.1f%%", hs), accent: AppTheme.Colors.csOrange)
                metricTile(label: "HOURS", value: String(format: "%.0f", hours), accent: AppTheme.Colors.ctBlue)
            }
        }
        .tacticalCard()
    }

    private func metricTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.gunmetalGray)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func faceitBadge(_ stats: PlayerOverviewStats) -> some View {
        if let faceit = stats.faceitStats {
            HStack(spacing: 14) {
                FaceitSkillLevelBadge(level: faceit.skillLevel, progress: faceit.levelProgress)

                VStack(alignment: .leading, spacing: 4) {
                    Text(faceit.nickname)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text("\(faceit.elo) ELO · Level \(faceit.skillLevel)")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.faceitLevelColor(faceit.skillLevel))
                }

                Spacer()

                Image(systemName: "flame.fill")
                    .foregroundStyle(AppTheme.faceitLevelColor(faceit.skillLevel))
            }
            .tacticalCard(accentBorder: AppTheme.faceitLevelColor(faceit.skillLevel).opacity(0.35))
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(AppTheme.Colors.csOrange)
            Text("Loading your stats…")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .tacticalCard()
    }

    private var emptyStatsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.Colors.csOrange)
            Text("No stats yet")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Connect your Steam Web API Key in Settings to see K/D, win rate, and more.")
                .font(AppTheme.Fonts.bodyRegular)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                selectedTab = .settings
            } label: {
                Text("OPEN SETTINGS")
                    .font(AppTheme.Fonts.captionMono)
            }
            .buttonStyle(SecondaryActionButtonStyle(borderColor: AppTheme.Colors.csOrange))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .tacticalCard()
    }

    private var inventoryTile: some View {
        Button {
            selectedTab = .inventory
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Colors.csOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CS2 Inventory")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Browse your skins and wear")
                        .font(AppTheme.Fonts.captionMono)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(16)
            .background(AppTheme.Colors.gunmetalGray)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
