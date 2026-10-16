import SwiftUI

// MARK: - CS2 rank ladder

/// The 18-tier CS2 competitive/Wingman ladder (rank_id 1...18) with the tier
/// color used to render the rank emblems. Names follow the in-game ladder.
enum CS2RankCatalog {
    struct Info: Sendable {
        let name: String
        let abbreviation: String
        let color: Color
    }

    private static let table: [UInt32: Info] = [
        1: Info(name: "Silver I", abbreviation: "S1", color: Color(white: 0.60)),
        2: Info(name: "Silver II", abbreviation: "S2", color: Color(white: 0.64)),
        3: Info(name: "Silver III", abbreviation: "S3", color: Color(white: 0.68)),
        4: Info(name: "Silver IV", abbreviation: "S4", color: Color(white: 0.72)),
        5: Info(name: "Silver Elite", abbreviation: "SE", color: Color(white: 0.76)),
        6: Info(name: "Silver Elite Master", abbreviation: "SEM", color: Color(white: 0.80)),
        7: Info(name: "Gold Nova I", abbreviation: "GN1", color: Color(red: 0.85, green: 0.70, blue: 0.25)),
        8: Info(name: "Gold Nova II", abbreviation: "GN2", color: Color(red: 0.87, green: 0.72, blue: 0.25)),
        9: Info(name: "Gold Nova III", abbreviation: "GN3", color: Color(red: 0.90, green: 0.74, blue: 0.25)),
        10: Info(name: "Gold Nova Master", abbreviation: "GNM", color: Color(red: 0.93, green: 0.77, blue: 0.27)),
        11: Info(name: "Master Guardian I", abbreviation: "MG1", color: Color(red: 0.30, green: 0.55, blue: 0.95)),
        12: Info(name: "Master Guardian II", abbreviation: "MG2", color: Color(red: 0.30, green: 0.55, blue: 0.95)),
        13: Info(name: "Master Guardian Elite", abbreviation: "MGE", color: Color(red: 0.35, green: 0.60, blue: 0.98)),
        14: Info(name: "Distinguished Master Guardian", abbreviation: "DMG", color: Color(red: 0.42, green: 0.66, blue: 1.00)),
        15: Info(name: "Legendary Eagle", abbreviation: "LE", color: Color(red: 0.60, green: 0.40, blue: 0.95)),
        16: Info(name: "Legendary Eagle Master", abbreviation: "LEM", color: Color(red: 0.65, green: 0.45, blue: 0.98)),
        17: Info(name: "Supreme Master First Class", abbreviation: "SMFC", color: Color(red: 0.95, green: 0.45, blue: 0.65)),
        18: Info(name: "Global Elite", abbreviation: "GE", color: Color(red: 0.95, green: 0.78, blue: 0.25))
    ]

    static func info(for rankID: UInt32) -> Info {
        table[rankID] ?? Info(name: "Rank \(rankID)", abbreviation: "R\(rankID)", color: AppTheme.Colors.textSecondary)
    }

    static func name(for rankID: UInt32) -> String {
        info(for: rankID).name
    }
}

// MARK: - Rank emblem

/// A Valorant-style rank emblem: a filled shape (circle for the current rank,
/// triangle for the peak/best) tinted by the rank tier, with the rank
/// abbreviation overlaid.
struct RankEmblem: View {
    enum EmblemShape {
        case circle
        case triangle
    }

    let rankID: UInt32
    let shape: EmblemShape

    var body: some View {
        let info = CS2RankCatalog.info(for: rankID)
        ZStack {
            switch shape {
            case .circle:
                Circle().fill(info.color.opacity(0.92))
            case .triangle:
                Triangle().fill(info.color.opacity(0.92))
            }
            Text(info.abbreviation)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 3)
        }
        .frame(width: 46, height: 46)
        .shadow(color: info.color.opacity(0.35), radius: 3, y: 1)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Ranked-mode overview card

/// The "RANKED MODE" card shown under the Premier rating card: the current
/// Wingman rank and the best competitive map, plus a "View all maps" action.
struct RankedModeOverviewCard: View {
    let wingman: PlayerRankingInfo?
    let competitive: PlayerRankingInfo?
    let lastUpdated: Date?

    @State private var showingAllMaps = false

    private var bestMap: PerMapRank? {
        guard let competitive else { return nil }
        return competitive.perMapRanks.max(by: { $0.rankID < $1.rankID })
    }

    private var hasMaps: Bool {
        guard let competitive else { return false }
        return !competitive.perMapRanks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RANKED MODE")
                    .font(AppTheme.Fonts.sectionTitle)
                    .foregroundStyle(AppTheme.Colors.csOrange)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                rankTile(
                    title: "WINGMAN",
                    currentRankID: wingman?.rankID,
                    peakRankID: wingman?.highestRank,
                    subtitle: wingman.map { CS2RankCatalog.name(for: $0.rankID) },
                    detail: wingman.map { "\($0.wins) wins" },
                    emptyText: "No Wingman rank yet"
                )

                rankTile(
                    title: "BEST MAP",
                    currentRankID: bestMap?.rankID,
                    peakRankID: competitive?.highestRank,
                    subtitle: bestMap.map { SteamMapCatalog.displayName(forGCID: $0.mapID) },
                    detail: bestMap.map { "\(CS2RankCatalog.name(for: $0.rankID)) · \($0.wins) wins" },
                    emptyText: "No competitive map ranks yet"
                )
            }

            Button {
                showingAllMaps = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("VIEW ALL MAPS")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.csOrange)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Colors.gunmetalElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!hasMaps)

            lastUpdatedLine
        }
        .tacticalCard(accentBorder: AppTheme.Colors.csOrange.opacity(0.3))
        .sheet(isPresented: $showingAllMaps) {
            AllMapsRankSheet(perMapRanks: competitive?.perMapRanks ?? [])
        }
    }

    @ViewBuilder
    private func rankTile(
        title: String,
        currentRankID: UInt32?,
        peakRankID: UInt32?,
        subtitle: String?,
        detail: String?,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.ctBlue)

            HStack(spacing: 10) {
                emblem(currentRankID, shape: .circle, label: "NOW")
                emblem(peakRankID, shape: .triangle, label: "PEAK")
            }

            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let detail {
                Text(detail)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            } else {
                Text(emptyText)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.gunmetalElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func emblem(_ rankID: UInt32?, shape: RankEmblem.EmblemShape, label: String) -> some View {
        VStack(spacing: 3) {
            if let rankID, rankID > 0 {
                RankEmblem(rankID: rankID, shape: shape)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Colors.gunmetalGray)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "minus")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    )
            }
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var lastUpdatedLine: some View {
        if let lastUpdated {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated \(lastUpdated, style: .relative)")
            }
            .font(AppTheme.Fonts.captionMono)
            .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
}

// MARK: - All-maps sheet

/// Lists every competitive map rank (map, rank, wins), highest rank first.
struct AllMapsRankSheet: View {
    let perMapRanks: [PerMapRank]

    @Environment(\.dismiss) private var dismiss

    private var sortedRanks: [PerMapRank] {
        perMapRanks.sorted { $0.rankID > $1.rankID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.oledBlack
                    .ignoresSafeArea()

                if sortedRanks.isEmpty {
                    ContentUnavailableView(
                        "No competitive maps yet",
                        systemImage: "map",
                        description: Text("Play competitive matches to establish per-map ranks.")
                    )
                } else {
                    List {
                        ForEach(sortedRanks, id: \.mapID) { rank in
                            mapRow(rank)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Competitive Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func mapRow(_ rank: PerMapRank) -> some View {
        let code = SteamMapCatalog.mapCode(forGCID: rank.mapID)
        let descriptor = code.map { SteamMapCatalog.descriptor(for: $0) }
        let info = CS2RankCatalog.info(for: rank.rankID)

        return HStack(spacing: 12) {
            Image(systemName: descriptor?.iconName ?? "map.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.Colors.csOrange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(SteamMapCatalog.displayName(forGCID: rank.mapID))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(info.name)
                    .font(AppTheme.Fonts.captionMono)
                    .foregroundStyle(info.color)
            }

            Spacer()

            Text("\(rank.wins) wins")
                .font(AppTheme.Fonts.captionMono)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(AppTheme.Colors.gunmetalGray)
    }
}
