import SwiftUI

public struct AllWeaponsView: View {
    public let weapons: [SteamWeaponStatSummary]

    @State private var selectedCategory: WeaponCategory = .all
    @State private var selectedFaction: StatsFactionFilter = .both
    @State private var searchText: String = ""

    public init(weapons: [SteamWeaponStatSummary]) {
        self.weapons = weapons
    }

    private var filteredWeapons: [SteamWeaponStatSummary] {
        weapons.filter { weapon in
            let matchesCategory = (selectedCategory == .all) || (weapon.category == selectedCategory)
            let matchesFaction = (selectedFaction == .both) || weapon.faction.matches(selectedFaction)
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                weapon.displayName.localizedCaseInsensitiveContains(searchText) ||
                weapon.id.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesFaction && matchesSearch
        }
    }

    private var maxKillsInSelection: Int {
        max(filteredWeapons.map(\.kills).max() ?? 1, 1)
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        Text("FACTION FILTER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Faction", selection: $selectedFaction) {
                            ForEach(StatsFactionFilter.allCases) { faction in
                                Text(faction.rawValue).tag(faction)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 16)

                    categoryFilterBar
                }
                .padding(.vertical, 10)
                .background(AppTheme.Colors.oledBlack)

                ScrollView {
                    if filteredWeapons.isEmpty {
                        emptyWeaponsState
                            .padding(.top, 48)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(filteredWeapons.enumerated()), id: \.element.id) { index, weapon in
                                weaponDetailCard(weapon: weapon, rank: index + 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("WEAPON MASTERY")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search weapon (e.g. AK-47, AWP, Deagle)"
        )
    }

    // MARK: - Category Selector Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WeaponCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? AppTheme.Colors.csOrange
                                    : AppTheme.Colors.gunmetalGray
                            )
                            .foregroundStyle(isSelected ? .black : .white)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Color.clear : AppTheme.Colors.borderSubtle,
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Weapon Detail Row Card

    private func weaponDetailCard(weapon: SteamWeaponStatSummary, rank: Int) -> some View {
        let ratio = min(max(Double(weapon.kills) / Double(maxKillsInSelection), 0.03), 1.0)
        let factionBadgeColor: Color = weapon.faction == .terrorist
            ? AppTheme.Colors.csOrange
            : (weapon.faction == .counterTerrorist ? AppTheme.Colors.ctBlue : .secondary)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("#\(rank)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .frame(width: 28, height: 28)
                    .background(rank <= 3 ? AppTheme.Colors.csOrange.opacity(0.2) : Color.white.opacity(0.06))
                    .foregroundStyle(rank <= 3 ? AppTheme.Colors.csOrange : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(weapon.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(weapon.faction.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(factionBadgeColor.opacity(0.18))
                            .foregroundStyle(factionBadgeColor)
                            .clipShape(Capsule())
                    }

                    Text(weapon.category.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(weapon.kills.formatted())")
                        .font(.title3.monospacedDigit().weight(.black))
                        .foregroundStyle(AppTheme.Colors.csOrange)
                    Text("TOTAL KILLS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 7)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.Colors.csOrange.opacity(0.75),
                                    AppTheme.Colors.csOrange
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * ratio, 10), height: 7)
                }
            }
            .frame(height: 7)

            HStack(spacing: 0) {
                weaponMetricPill(
                    label: "Accuracy",
                    value: String(format: "%.1f%%", weapon.accuracyPercentage),
                    color: AppTheme.Colors.ctBlue
                )

                Divider()
                    .frame(height: 22)
                    .overlay(Color.white.opacity(0.08))

                weaponMetricPill(
                    label: "Est. HS %",
                    value: String(format: "%.1f%%", weapon.headshotPercentage),
                    color: AppTheme.Colors.statusSuccess
                )

                Divider()
                    .frame(height: 22)
                    .overlay(Color.white.opacity(0.08))

                weaponMetricPill(
                    label: "Shots Hit",
                    value: "\(weapon.shotsHit.formatted()) / \(weapon.shotsFired.formatted())",
                    color: .secondary
                )
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(AppTheme.Colors.gunmetalGray)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func weaponMetricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(color == .secondary ? .white : color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyWeaponsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.Colors.csOrange)
            Text("No Matching Weapons")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Try switching the weapon category, faction filter, or clearing your search query.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}