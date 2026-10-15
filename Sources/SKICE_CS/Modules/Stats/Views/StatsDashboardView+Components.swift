import SwiftUI

// MARK: - Map Performance Card Component (Clean Map Name + Rounds & Win Rate)

struct MapPerformanceCard: View {
    let mapStat: SteamMapStatSummary

    var body: some View {
        let winRatio = min(max(mapStat.winRatePercentage / 100.0, 0.0), 1.0)
        let accentColor = mapStat.winRatePercentage >= 50.0 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.csOrange

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
                        .fill(AppTheme.Colors.statusDanger.opacity(0.35))
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
                    .foregroundStyle(AppTheme.Colors.statusSuccess)
                Spacer()
                Text("\(mapStat.roundsLost.formatted()) Lost")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.statusDanger)
            }
        }
        .padding(14)
        .frame(width: 178)
        .background(AppTheme.Colors.gunmetalGray)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Reusable Stat Metric Card

struct StatMetricCard: View {
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
        .background(AppTheme.Colors.gunmetalGray)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - FACEIT Skill Level 1-10 Vector Badge

struct FaceitSkillLevelBadge: View {
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