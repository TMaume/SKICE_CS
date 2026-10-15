import SwiftUI

public struct MapDetailView: View {
    public let mapStat: SteamMapStatSummary

    @Environment(\.dismiss) private var dismiss

    public init(mapStat: SteamMapStatSummary) {
        self.mapStat = mapStat
    }

    private var statusBadgeColor: Color {
        switch mapStat.victoryStatus {
        case .dominant, .positive:
            return AppTheme.Colors.statusSuccess
        case .balanced:
            return AppTheme.Colors.csOrange
        case .challenging:
            return AppTheme.Colors.statusDanger
        case .unplayed:
            return .secondary
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.oledBlack
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        mapHeaderBanner
                        coreMapMetricsSection
                        if mapStat.hasSideBreakdownInSchema {
                            sideDominanceSection
                        } else {
                            schemaHonestyNoticeCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(mapStat.displayName.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.csOrange)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 1. Header Banner with Clean Map Name & Victory Status Badge

    private var mapHeaderBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            statusBadgeColor.opacity(0.24),
                            AppTheme.Colors.gunmetalGray,
                            AppTheme.Colors.oledBlack
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack {
                Spacer()
                Image(systemName: mapStat.iconName)
                    .font(.system(size: 82, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.06))
                    .padding(.trailing, 18)
                    .padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(mapStat.victoryStatus.rawValue)
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(statusBadgeColor.opacity(0.2))
                        .foregroundStyle(statusBadgeColor)
                        .clipShape(Capsule())

                    Text(mapStat.isActiveDuty ? "ACTIVE DUTY POOL" : "RESERVE POOL")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }

                Text(mapStat.displayName)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(mapStat.tacticalProfile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(statusBadgeColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 2. Verified Valve Schema Metrics (Rounds Played, Rounds Won, Win Rate %)

    private var coreMapMetricsSection: some View {
        let winRatio = min(max(mapStat.winRatePercentage / 100.0, 0.0), 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            Text("LIFETIME MAP TELEMETRY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if mapStat.roundsPlayed > 0 {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        metricColumnCard(
                            title: "ROUNDS PLAYED",
                            value: mapStat.roundsPlayed.formatted(),
                            subtitle: "Total Rounds",
                            color: .white
                        )

                        metricColumnCard(
                            title: "ROUNDS WON",
                            value: mapStat.roundsWon.formatted(),
                            subtitle: "\(mapStat.roundsLost.formatted()) Lost",
                            color: AppTheme.Colors.statusSuccess
                        )

                        metricColumnCard(
                            title: "WIN RATE %",
                            value: String(format: "%.1f%%", mapStat.winRatePercentage),
                            subtitle: "Round Win Ratio",
                            color: statusBadgeColor
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Round Win / Loss Split")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(mapStat.roundsWon.formatted())W – \(mapStat.roundsLost.formatted())L")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppTheme.Colors.statusDanger.opacity(0.35))
                                    .frame(height: 8)

                                Capsule()
                                    .fill(statusBadgeColor)
                                    .frame(width: max(geo.size.width * winRatio, 8), height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
                .padding(16)
                .background(AppTheme.Colors.gunmetalGray)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.Colors.csOrange)
                    Text("No recorded rounds found for \(mapStat.displayName) in this Steam account's career statistics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.gunmetalGray)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func metricColumnCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.monospacedDigit().weight(.black))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 3. Side Dominance (Only Displayed When Present in Schema)

    private var sideDominanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SIDE DOMINANCE (T VS CT)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let tRate = mapStat.terroristWinRatePercentage {
                    metricColumnCard(
                        title: "T-SIDE WIN %",
                        value: String(format: "%.1f%%", tRate),
                        subtitle: "Terrorist Side",
                        color: AppTheme.Colors.csOrange
                    )
                }

                if let ctRate = mapStat.counterTerroristWinRatePercentage {
                    metricColumnCard(
                        title: "CT-SIDE WIN %",
                        value: String(format: "%.1f%%", ctRate),
                        subtitle: "Counter-Terrorist Side",
                        color: AppTheme.Colors.ctBlue
                    )
                }
            }
            .padding(16)
            .background(AppTheme.Colors.gunmetalGray)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var schemaHonestyNoticeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.Colors.ctBlue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Verified Valve Schema Telemetry")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text("Valve's ISteamUserStats endpoint only exposes cumulative rounds played and rounds won per map. Per-map K/D and side splits are intentionally omitted here to avoid synthetic or placeholder numbers, and will be powered by Game Coordinator / GSI telemetry.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.gunmetalGray)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}