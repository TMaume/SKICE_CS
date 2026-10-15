import SwiftUI

public struct StatsDashboardView: View {
    public let steamID64: String?
    @State private var viewModel = StatsViewModel()

    private let metricGridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(steamID64: String? = nil) {
        self.steamID64 = steamID64
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    topFilterControlsSection

                    if viewModel.isLoading && viewModel.overviewStats == nil {
                        loadingStateView
                    } else if viewModel.selectedFilter == .faceit && !viewModel.isFaceitConnected {
                        // Strict isolation: never fall back to displaying Steam numbers when FACEIT is selected
                        noFaceitProfileConnectedStateView
                    } else {
                        if viewModel.selectedFilter != .steam && viewModel.isFaceitConnected {
                            faceitHeroSection
                        }

                        if let stats = viewModel.overviewStats, stats.hasAnyData {
                            keyMetricsGrid(stats: stats)

                            if viewModel.selectedFilter != .faceit,
                               let activeSteam = viewModel.activeSteamStats {
                                factionDominanceCard(steam: activeSteam)
                            }

                            if viewModel.selectedFilter != .steam,
                               let faceit = stats.faceitStats {
                                faceitRecentMatchesSection(
                                    faceit: faceit,
                                    matches: viewModel.filteredFaceitMatches
                                )
                            }

                            if viewModel.selectedFilter != .faceit {
                                mapPerformanceSection(stats: stats)
                                topWeaponsSection(stats: stats)
                            }

                            lastUpdatedFooter(date: stats.lastUpdated)
                        } else {
                            emptyStateView
                        }
                    }

                    statusDiagnosticsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await viewModel.refreshStats(explicitSteamID64: steamID64)
            }
        }
        .navigationTitle("CS2 // STATS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.isShowingFaceitConfigSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(AppTheme.Colors.csOrange)
                    }
                    .accessibilityLabel("Configure FACEIT")

                    Button {
                        Task {
                            await viewModel.refreshStats(explicitSteamID64: steamID64)
                        }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .tint(AppTheme.Colors.csOrange)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(AppTheme.Colors.csOrange)
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isRefreshing)
                    .accessibilityLabel("Refresh Stats")
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingFaceitConfigSheet) {
            faceitConfigurationSheet
        }
        .sheet(item: $viewModel.selectedMapForSheet) { selectedMap in
            MapDetailView(mapStat: selectedMap)
        }
        .task(id: steamID64) {
            await viewModel.loadStatsIfNeeded(explicitSteamID64: steamID64)
        }
    }

    // MARK: - Top Filter Area (Platform + Faction [Both | T | CT] + Timeframe)

    private var topFilterControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Stats Source", selection: $viewModel.selectedFilter) {
                    ForEach(StatsPlatformFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedFilter != .faceit {
                    Picker("Faction", selection: $viewModel.selectedFaction) {
                        ForEach(StatsFactionFilter.allCases) { faction in
                            Text(faction.rawValue).tag(faction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                }
            }

            timeFrameSelectorSection
        }
    }

    // MARK: - Time Frame Selector & Snapshot Status Badge

    private var timeFrameSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatsTimeFrame.allCases) { timeframe in
                        let isSelected = viewModel.selectedTimeFrame == timeframe
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                viewModel.selectedTimeFrame = timeframe
                            }
                        } label: {
                            Text(timeframe.rawValue)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                        ? AppTheme.Colors.csOrange
                                        : AppTheme.statsCardSurface
                                )
                                .foregroundStyle(isSelected ? .black : .white)
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isSelected ? Color.clear : AppTheme.statsCardBorder,
                                            lineWidth: 1
                                        )
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.selectedTimeFrame == .custom {
                HStack(spacing: 12) {
                    DatePicker(
                        "From",
                        selection: $viewModel.customStartDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .colorScheme(.dark)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DatePicker(
                        "To",
                        selection: $viewModel.customEndDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .colorScheme(.dark)

                    Spacer()
                }
                .padding(10)
                .background(AppTheme.statsCardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let badgeText = viewModel.snapshotStatusBadgeText {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isShowingDelta ? "chart.line.uptrend.xyaxis" : "clock.badge.checkmark")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isShowingDelta ? AppTheme.statsPositiveGreen : AppTheme.Colors.csOrange)

                    Text(badgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.isShowingDelta ? AppTheme.statsPositiveGreen : .secondary)

                    if !viewModel.isShowingDelta {
                        Text("• Showing Cumulative Baseline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.statsCardSurface.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(AppTheme.statsCardBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - 2. Dedicated Empty State When FACEIT Is Selected Without Credentials

    private var noFaceitProfileConnectedStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.csOrange.opacity(0.15))
                    .frame(width: 74, height: 74)

                Image(systemName: "flame.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.csOrange)
            }

            VStack(spacing: 8) {
                Text("No FACEIT Profile Connected")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Connect your FACEIT API Key or Nickname in Settings to view match history, Elo, skill level, and per-match performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button {
                viewModel.isShowingFaceitConfigSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                    Text("Configure in Settings")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.Colors.csOrange)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.Colors.csOrange.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - FACEIT Level Badge & ELO Progress Section

    @ViewBuilder
    private var faceitHeroSection: some View {
        if let faceit = viewModel.overviewStats?.faceitStats {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FaceitSkillLevelBadge(level: faceit.skillLevel, progress: faceit.levelProgress)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(faceit.nickname)
                                .font(.title3.bold())
                                .foregroundStyle(.white)

                            Text(faceit.region)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Colors.csOrange.opacity(0.2))
                                .foregroundStyle(AppTheme.Colors.csOrange)
                                .clipShape(Capsule())

                            Text(faceit.country)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 12) {
                            Label("\(faceit.elo) ELO", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.faceitLevelColor(faceit.skillLevel))

                            if let rank = faceit.regionalRank {
                                Label("#\(rank.formatted()) \(faceit.region)", systemImage: "globe.europe.africa.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.isShowingFaceitConfigSheet = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Level \(faceit.skillLevel) Floor: \(faceit.currentLevelFloorElo) ELO")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let needed = faceit.eloNeededForNextLevel, let target = faceit.nextLevelTargetElo {
                            Text("+\(needed) ELO to Level \(faceit.skillLevel + 1) (\(target))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.csOrange)
                        } else {
                            Text("Max Tier Reached (Level 10 Challenger)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.faceitLevelColor(10))
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 8)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.faceitLevelColor(faceit.skillLevel).opacity(0.75),
                                            AppTheme.faceitLevelColor(faceit.skillLevel)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geo.size.width * faceit.levelProgress, 10), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(16)
            .background(AppTheme.statsCardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.faceitLevelColor(faceit.skillLevel).opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 1. Clean Career Key Performance Metrics Grid

    private func keyMetricsGrid(stats: PlayerOverviewStats) -> some View {
        let filter = viewModel.selectedFilter
        let faction = viewModel.selectedFaction
        let activeSteam = viewModel.activeSteamStats
        let faceitWindowMatches = viewModel.filteredFaceitMatches
        let factionSummary = activeSteam?.factionSummary(for: faction)

        let kd = stats.kdRatio(for: filter, activeSteam: activeSteam)
        let winRate = stats.winRatePercentage(
            for: filter,
            faction: faction,
            activeSteam: activeSteam,
            filteredFaceitMatches: faceitWindowMatches
        )
        let hs = stats.headshotPercentage(for: filter, activeSteam: activeSteam)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(filter == .faceit ? "FACEIT CAREER METRICS" : "LIFETIME CAREER METRICS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if filter != .faceit && faction != .both {
                    Text(faction.fullDisplayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(faction == .terrorist ? AppTheme.Colors.csOrange : AppTheme.statsAccentBlue)
                } else {
                    Text(viewModel.selectedTimeFrame.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.csOrange)
                }
            }

            LazyVGrid(columns: metricGridColumns, spacing: 12) {
                // Card 1: K/D Ratio (or Faction Kills when T/CT filter is active)
                StatMetricCard(
                    title: faction != .both && filter != .faceit ? "\(faction.rawValue)-SIDE WEAPON KILLS" : "K/D RATIO",
                    value: faction != .both && filter != .faceit
                        ? "\((factionSummary?.factionWeaponKills ?? 0).formatted())"
                        : String(format: "%.2f", kd),
                    subtitle: kdSubtitle(activeSteam: activeSteam, filter: filter, faction: faction),
                    icon: "scope",
                    accentColor: kd >= 1.0 ? AppTheme.statsPositiveGreen : AppTheme.Colors.csOrange
                )

                // Card 2: Win Rate % (or Faction Dominance %)
                StatMetricCard(
                    title: winRateCardTitle(filter: filter, faction: faction),
                    value: String(format: "%.1f%%", winRate),
                    subtitle: winRateSubtitle(
                        stats: stats,
                        activeSteam: activeSteam,
                        factionSummary: factionSummary,
                        filter: filter,
                        faction: faction
                    ),
                    icon: "trophy.fill",
                    accentColor: winRate >= 50.0 ? AppTheme.statsPositiveGreen : AppTheme.statsAccentBlue
                )

                // Card 3: Headshot %
                StatMetricCard(
                    title: "HEADSHOT %",
                    value: String(format: "%.1f%%", hs),
                    subtitle: hsSubtitle(activeSteam: activeSteam, filter: filter),
                    icon: "viewfinder.circle.fill",
                    accentColor: AppTheme.Colors.csOrange
                )

                // Card 4: FACEIT ADR (only on FACEIT) or Verified Weapon Accuracy on Steam
                if filter == .faceit, let faceitAdr = stats.faceitStats?.adr {
                    StatMetricCard(
                        title: "FACEIT ADR",
                        value: String(format: "%.1f HP", faceitAdr),
                        subtitle: "Avg. Damage / Round",
                        icon: "bolt.shield.fill",
                        accentColor: faceitAdr >= 80.0 ? AppTheme.statsPositiveGreen : AppTheme.statsAccentBlue
                    )
                } else {
                    let accuracy = faction != .both
                        ? (factionSummary?.factionAccuracyPercentage ?? 0.0)
                        : (activeSteam?.accuracyPercentage ?? 0.0)
                    StatMetricCard(
                        title: faction != .both ? "\(faction.rawValue)-SIDE ACCURACY" : "ACCURACY %",
                        value: String(format: "%.1f%%", accuracy),
                        subtitle: accuracySubtitle(activeSteam: activeSteam, factionSummary: factionSummary, faction: faction),
                        icon: "target",
                        accentColor: AppTheme.statsAccentBlue
                    )
                }

                // Card 5: MVPs & Objectives (Bombs Planted / Defused)
                StatMetricCard(
                    title: objectiveOrMvpTitle(filter: filter, faction: faction),
                    value: mvpOrObjectiveValue(
                        stats: stats,
                        activeSteam: activeSteam,
                        factionSummary: factionSummary,
                        filter: filter,
                        faction: faction
                    ),
                    subtitle: mvpOrObjectiveSubtitle(
                        stats: stats,
                        activeSteam: activeSteam,
                        factionSummary: factionSummary,
                        filter: filter,
                        faction: faction
                    ),
                    icon: faction == .terrorist ? "flame.fill" : (faction == .counterTerrorist ? "wrench.and.screwdriver.fill" : "star.fill"),
                    accentColor: faction == .counterTerrorist ? AppTheme.statsAccentBlue : Color.yellow
                )

                // Card 6: Playtime / Total Matches
                StatMetricCard(
                    title: filter == .faceit ? "FACEIT MATCHES" : "TIME PLAYED",
                    value: playtimeOrMatchesValue(stats: stats, activeSteam: activeSteam, filter: filter),
                    subtitle: playtimeOrMatchesSubtitle(stats: stats, activeSteam: activeSteam, filter: filter),
                    icon: "clock.fill",
                    accentColor: AppTheme.statsAccentBlue
                )
            }
        }
    }

    // MARK: - 3. Faction / Team Dominance & Objective Breakdown Card

    private func factionDominanceCard(steam: SteamPlayerStats) -> some View {
        let summary = steam.factionSummary(for: viewModel.selectedFaction)
        let tShare = min(max(summary.terroristDominancePercentage / 100.0, 0.05), 0.95)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "FACTION DOMINANCE (T VS CT)",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(
                    String(
                        format: "T %.1f%% • CT %.1f%%",
                        summary.terroristDominancePercentage,
                        summary.counterTerroristDominancePercentage
                    )
                )
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
            }

            GeometryReader { geo in
                HStack(spacing: 4) {
                    Capsule()
                        .fill(AppTheme.Colors.csOrange)
                        .frame(width: max(geo.size.width * tShare - 2, 12), height: 8)

                    Capsule()
                        .fill(AppTheme.statsAccentBlue)
                        .frame(width: max(geo.size.width * (1.0 - tShare) - 2, 12), height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("T-SIDE (ATTACK)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.csOrange)
                    Text("\(summary.terroristRoundsWon.formatted()) Rounds Won")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(steam.bombsPlanted.formatted()) Bombs Planted")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 32)
                    .overlay(Color.white.opacity(0.08))

                VStack(alignment: .trailing, spacing: 2) {
                    Text("CT-SIDE (DEFENSE)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.statsAccentBlue)
                    Text("\(summary.counterTerroristRoundsWon.formatted()) Rounds Won")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(steam.bombsDefused.formatted()) Bombs Defused")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.statsCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - FACEIT v4 Real Match History Section

    private func faceitRecentMatchesSection(
        faceit: FaceitPlayerStats,
        matches: [FaceitMatchSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FACEIT MATCH HISTORY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 5) {
                    ForEach(Array(faceit.recentResults.enumerated()), id: \.offset) { _, isWin in
                        Text(isWin ? "W" : "L")
                            .font(.caption2.weight(.heavy))
                            .frame(width: 22, height: 22)
                            .background(
                                (isWin ? AppTheme.statsPositiveGreen : AppTheme.statsDangerRed)
                                    .opacity(0.2)
                            )
                            .foregroundStyle(isWin ? AppTheme.statsPositiveGreen : AppTheme.statsDangerRed)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            if matches.isEmpty {
                Text("No FACEIT matches recorded within the selected time window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.statsCardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 10) {
                    ForEach(matches.prefix(5)) { match in
                        faceitMatchRowCard(match: match)
                    }
                }
            }
        }
    }

    private func faceitMatchRowCard(match: FaceitMatchSummary) -> some View {
        let resultColor = match.isWin ? AppTheme.statsPositiveGreen : AppTheme.statsDangerRed

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(match.isWin ? "VICTORY" : "DEFEAT")
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(resultColor.opacity(0.18))
                    .foregroundStyle(resultColor)
                    .clipShape(Capsule())

                Text(match.mapDisplayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(match.gameMode.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.csOrange.opacity(0.18))
                    .foregroundStyle(AppTheme.Colors.csOrange)
                    .clipShape(Capsule())

                Spacer()

                Text(match.scoreDisplay)
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(resultColor)
            }

            HStack {
                Text("vs. \(match.opponentTeamName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(match.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if match.hasDetailedScoreboard {
                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 0) {
                    if let kills = match.kills {
                        miniMatchStat(label: "Kills", value: "\(kills)", color: .white)
                    }
                    if let deaths = match.deaths {
                        miniMatchStat(label: "Deaths", value: "\(deaths)", color: .white)
                    }
                    if let kd = match.kdRatio {
                        miniMatchStat(
                            label: "K/D",
                            value: String(format: "%.2f", kd),
                            color: kd >= 1.0 ? AppTheme.statsPositiveGreen : AppTheme.Colors.csOrange
                        )
                    }
                    if let mvps = match.mvps {
                        miniMatchStat(label: "MVPs", value: "\(mvps)", color: .yellow)
                    }
                    if let adr = match.adr {
                        miniMatchStat(
                            label: "ADR",
                            value: String(format: "%.1f", adr),
                            color: AppTheme.statsAccentBlue
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(resultColor.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func miniMatchStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Interactive Map Performance Breakdown (Tappable -> MapDetailView Sheet)

    @ViewBuilder
    private func mapPerformanceSection(stats: PlayerOverviewStats) -> some View {
        let activeSteam = viewModel.activeSteamStats ?? stats.steamStats
        if let maps = activeSteam?.mapStats, !maps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MAP PERFORMANCE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap a map for details")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.csOrange)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(maps) { mapStat in
                            Button {
                                viewModel.selectedMapForSheet = mapStat
                            } label: {
                                MapPerformanceCard(mapStat: mapStat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Expandable Weapon Mastery Section

    @ViewBuilder
    private func topWeaponsSection(stats: PlayerOverviewStats) -> some View {
        let activeSteam = viewModel.activeSteamStats ?? stats.steamStats
        if let activeSteam {
            let filteredWeapons = activeSteam.weapons(for: viewModel.selectedFaction)
            let topThree = Array(filteredWeapons.prefix(3))
            let maxKills = max(topThree.first?.kills ?? 1, 1)

            if !topThree.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(
                            viewModel.selectedFaction == .both
                                ? "TOP WEAPON MASTERY"
                                : "TOP \(viewModel.selectedFaction.rawValue)-SIDE WEAPONS"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                        Spacer()

                        NavigationLink {
                            AllWeaponsView(weapons: activeSteam.allWeapons)
                        } label: {
                            HStack(spacing: 4) {
                                Text("View All Weapons (\(activeSteam.allWeapons.count))")
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.csOrange)
                        }
                    }

                    VStack(spacing: 14) {
                        ForEach(topThree) { weapon in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(weapon.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Text(weapon.faction.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.07))
                                        .foregroundStyle(.secondary)
                                        .clipShape(Capsule())

                                    Spacer()

                                    Text("\(weapon.kills.formatted()) kills")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(AppTheme.Colors.csOrange)

                                    Text("• \(String(format: "%.1f%%", weapon.accuracyPercentage)) acc")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.07))
                                            .frame(height: 6)

                                        Capsule()
                                            .fill(AppTheme.Colors.csOrange)
                                            .frame(
                                                width: max(geo.size.width * (Double(weapon.kills) / Double(maxKills)), 8),
                                                height: 6
                                            )
                                    }
                                }
                                .frame(height: 6)
                            }
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.08))

                        NavigationLink {
                            AllWeaponsView(weapons: activeSteam.allWeapons)
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet.below.rectangle")
                                Text("View All Weapons")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(activeSteam.allWeapons.count) Weapons")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.csOrange)
                            .padding(.top, 2)
                        }
                    }
                    .padding(16)
                    .background(AppTheme.statsCardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.statsCardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Diagnostics & Error Banners

    @ViewBuilder
    private var statusDiagnosticsSection: some View {
        VStack(spacing: 10) {
            if let steamErr = viewModel.steamErrorMessage, viewModel.selectedFilter != .faceit {
                diagnosticBanner(title: "Steam Web API Notice", message: steamErr, icon: "exclamationmark.shield.fill")
            }

            if let faceitErr = viewModel.faceitErrorMessage, viewModel.selectedFilter != .steam {
                diagnosticBanner(title: "FACEIT API Notice", message: faceitErr, icon: "flame.circle.fill")
            }
        }
    }

    private func diagnosticBanner(title: String, message: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.csOrange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.csOrange.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Loading & Empty States

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.Colors.csOrange)
            Text("Syncing CS2 statistics from Steam & FACEIT...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Colors.csOrange)

            Text("No Player Statistics Loaded")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Configure your SteamID64 & Steam Web API Key in the Profile tab, or link your FACEIT Nickname and Client API Key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                Task {
                    await viewModel.refreshStats(explicitSteamID64: steamID64)
                }
            } label: {
                Label("Retry Sync", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppTheme.Colors.csOrange)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.statsCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func lastUpdatedFooter(date: Date) -> some View {
        Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: - FACEIT Configuration Sheet

    private var faceitConfigurationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("FACEIT Nickname or Player ID", text: $viewModel.faceitIdentifierInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Player Lookup")
                } footer: {
                    Text("Accepts an exact FACEIT Nickname (e.g. ZywOo), a FACEIT Player UUID, or leave blank to resolve via your SteamID64.")
                }

                Section {
                    SecureField("FACEIT v4 Client API Key (Bearer)", text: $viewModel.faceitAPIKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("FACEIT Open API v4 Key")
                } footer: {
                    Text("Stored locally in the iOS Keychain (Zero-Trust). Required by open.faceit.com/data/v4 endpoints.")
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.clearStatsCache()
                    } label: {
                        Label("Clear Cached Stats & Snapshots", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("FACEIT Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isShowingFaceitConfigSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Sync") {
                        Task {
                            await viewModel.saveFaceitConfigurationAndRefresh(explicitSteamID64: steamID64)
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Card Title & Subtitle Formatters

    private func winRateCardTitle(
        filter: StatsPlatformFilter,
        faction: StatsFactionFilter
    ) -> String {
        guard filter != .faceit, faction != .both else {
            return "WIN RATE %"
        }
        return "\(faction.rawValue)-SIDE DOMINANCE"
    }

    private func kdSubtitle(
        activeSteam: SteamPlayerStats?,
        filter: StatsPlatformFilter,
        faction: StatsFactionFilter
    ) -> String {
        if filter == .faceit {
            return "FACEIT Lifetime Avg."
        }
        if faction != .both, let steam = activeSteam {
            return String(format: "Career K/D: %.2f", steam.kdRatio)
        }
        if let steam = activeSteam {
            return "\(steam.totalKills.formatted()) K / \(steam.totalDeaths.formatted()) D"
        }
        return "Total Kills / Deaths"
    }

    private func winRateSubtitle(
        stats: PlayerOverviewStats,
        activeSteam: SteamPlayerStats?,
        factionSummary: FactionPerformanceSummary?,
        filter: StatsPlatformFilter,
        faction: StatsFactionFilter
    ) -> String {
        if filter == .faceit, let faceit = stats.faceitStats {
            return "\(faceit.totalWins.formatted()) / \(faceit.totalMatches.formatted()) Matches Won"
        }
        if faction != .both, let factionSummary {
            return "\(factionSummary.selectedSideRoundsWon.formatted()) \(faction.rawValue)-Side Rounds Won"
        }
        if let steam = activeSteam {
            if steam.matchesPlayed > 0 && steam.matchesWon <= steam.matchesPlayed {
                return "\(steam.matchesWon.formatted()) / \(steam.matchesPlayed.formatted()) Matches Won"
            }
            if steam.roundsPlayed > 0 {
                return "\(steam.roundsWon.formatted()) / \(steam.roundsPlayed.formatted()) Rounds Won"
            }
        }
        return "Lifetime Win Ratio"
    }

    private func hsSubtitle(activeSteam: SteamPlayerStats?, filter: StatsPlatformFilter) -> String {
        if filter == .faceit {
            return "FACEIT HS Ratio"
        }
        if let steam = activeSteam {
            return "\(steam.headshotKills.formatted()) HS Kills"
        }
        return "Headshot Precision"
    }

    private func accuracySubtitle(
        activeSteam: SteamPlayerStats?,
        factionSummary: FactionPerformanceSummary?,
        faction: StatsFactionFilter
    ) -> String {
        if faction != .both, let factionSummary {
            return "\(factionSummary.factionShotsHit.formatted()) / \(factionSummary.factionShotsFired.formatted()) Hit"
        }
        if let steam = activeSteam {
            return "\(steam.shotsHit.formatted()) / \(steam.shotsFired.formatted()) Hit"
        }
        return "Shots Hit / Fired"
    }

    private func objectiveOrMvpTitle(filter: StatsPlatformFilter, faction: StatsFactionFilter) -> String {
        if filter == .faceit {
            return "WIN STREAK"
        }
        switch faction {
        case .both:
            return "MVP COUNT"
        case .terrorist:
            return "BOMBS PLANTED"
        case .counterTerrorist:
            return "BOMBS DEFUSED"
        }
    }

    private func mvpOrObjectiveValue(
        stats: PlayerOverviewStats,
        activeSteam: SteamPlayerStats?,
        factionSummary: FactionPerformanceSummary?,
        filter: StatsPlatformFilter,
        faction: StatsFactionFilter
    ) -> String {
        if filter == .faceit, let faceit = stats.faceitStats {
            return "\(faceit.currentWinStreak) W"
        }
        if faction != .both, let factionSummary {
            return factionSummary.objectiveCount.formatted()
        }
        if let steam = activeSteam {
            return steam.mvpCount.formatted()
        }
        return "0"
    }

    private func mvpOrObjectiveSubtitle(
        stats: PlayerOverviewStats,
        activeSteam: SteamPlayerStats?,
        factionSummary: FactionPerformanceSummary?,
        filter: StatsPlatformFilter,
        faction: StatsFactionFilter
    ) -> String {
        if filter == .faceit, let faceit = stats.faceitStats {
            return "Best Streak: \(faceit.longestWinStreak) W"
        }
        if faction != .both, let factionSummary {
            return factionSummary.objectiveEfficiencySubtitle
        }
        if let steam = activeSteam {
            return "\(steam.bombsPlanted.formatted()) Planted • \(steam.bombsDefused.formatted()) Defused"
        }
        return "Career Objectives"
    }

    private func playtimeOrMatchesValue(
        stats: PlayerOverviewStats,
        activeSteam: SteamPlayerStats?,
        filter: StatsPlatformFilter
    ) -> String {
        if filter == .faceit, let faceit = stats.faceitStats {
            return faceit.totalMatches.formatted()
        }
        if let steam = activeSteam {
            return String(format: "%.0f hrs", steam.timePlayedHours)
        }
        return "0 hrs"
    }

    private func playtimeOrMatchesSubtitle(
        stats: PlayerOverviewStats,
        activeSteam: SteamPlayerStats?,
        filter: StatsPlatformFilter
    ) -> String {
        if filter == .faceit, let faceit = stats.faceitStats {
            return "\(faceit.totalWins.formatted()) Career Wins"
        }
        if let steam = activeSteam {
            return "\(steam.roundsPlayed.formatted()) Career Rounds"
        }
        return "Total Playtime"
    }
}

// MARK: - Map Performance Card Component (Clean Map Name + Rounds & Win Rate)

private struct MapPerformanceCard: View {
    let mapStat: SteamMapStatSummary

    var body: some View {
        let winRatio = min(max(mapStat.winRatePercentage / 100.0, 0.0), 1.0)
        let accentColor = mapStat.winRatePercentage >= 50.0 ? AppTheme.statsPositiveGreen : AppTheme.Colors.csOrange

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.csOrange.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: mapStat.iconName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.csOrange)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(mapStat.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(mapStat.isActiveDuty ? "Active Duty" : "Reserve Pool")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f%%", mapStat.winRatePercentage))
                    .font(.title3.monospacedDigit().weight(.black))
                    .foregroundStyle(accentColor)

                Spacer()

                Text("\(mapStat.roundsPlayed.formatted()) Rnds")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.statsDangerRed.opacity(0.35))
                        .frame(height: 6)

                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(geo.size.width * winRatio, 6), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(mapStat.roundsWon.formatted()) Won")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.statsPositiveGreen)
                Spacer()
                Text("\(mapStat.roundsLost.formatted()) Lost")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.statsDangerRed)
            }
        }
        .padding(14)
        .frame(width: 178)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.statsCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Reusable Stat Metric Card

private struct StatMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.statsCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.statsCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - FACEIT Skill Level 1-10 Vector Badge

private struct FaceitSkillLevelBadge: View {
    let level: Int
    let progress: Double

    var body: some View {
        let tierColor = AppTheme.faceitLevelColor(level)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tierColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("LVL")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(level)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(tierColor)
            }
        }
        .frame(width: 54, height: 54)
    }
}