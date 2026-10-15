import SwiftUI

/// Main CS2 Inventory screen supporting Grid/List toggles, rarity colors, verified trade-lock / untradable badges, and conditional debug access.
public struct InventoryView: View {
    public let steamID64: String

    @AppStorage("isDeveloperModeEnabled") private var isDeveloperModeEnabled: Bool = false

    @State private var viewModel: InventoryViewModel
    @State private var isGridView: Bool = true
    @State private var selectedItemForDetail: SkinItem?
    @State private var isShowingDebugSheet: Bool = false
    @State private var isShowingTradeUpCalculator: Bool = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 155, maximum: 210), spacing: 12)
    ]

    public init(
        steamID64: String,
        viewModel: InventoryViewModel = InventoryViewModel()
    ) {
        self.steamID64 = steamID64
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.items.isEmpty {
                    summaryHeaderBar
                    portfolioValueBar
                    filterControlBar
                }

                contentArea
            }
        }
        .navigationTitle("CS2 Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search skins, knives, collections..."
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isDeveloperModeEnabled {
                    Button {
                        isShowingDebugSheet = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .foregroundStyle(AppTheme.Colors.csOrange)
                    }
                    .accessibilityLabel("Open Debug Console")
                }

                Button {
                    isShowingTradeUpCalculator = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.Colors.csOrange)
                }
                .accessibilityLabel("Open Trade-Up Calculator")

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isGridView.toggle()
                    }
                } label: {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Toggle Layout")

                Button {
                    Task {
                        await viewModel.loadInventory(for: steamID64, forceRefresh: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh Inventory")
            }
        }
        .sheet(item: $selectedItemForDetail) { item in
            SkinDetailSheet(item: item, price: viewModel.price(for: item))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingTradeUpCalculator) {
            TradeUpCalculatorView(inventory: viewModel.items, priceStore: viewModel.priceStore)
        }
        .sheet(isPresented: $isShowingDebugSheet) {
            NavigationStack {
                DebugLogsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                isShowingDebugSheet = false
                            }
                            .foregroundStyle(AppTheme.Colors.csOrange)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: steamID64) {
            await viewModel.loadInventory(for: steamID64)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var summaryHeaderBar: some View {
        HStack(spacing: 14) {
            statPill(title: "TOTAL", value: "\(viewModel.totalItemsCount)", color: .white)
            statPill(title: "TRADABLE", value: "\(viewModel.tradableItemsCount)", color: AppTheme.Colors.statusSuccess)
            if viewModel.cooldownItemsCount > 0 {
                statPill(title: "COOLDOWN", value: "\(viewModel.cooldownItemsCount)", color: AppTheme.Colors.csOrange)
            }
            statPill(title: "UNTRADABLE", value: "\(viewModel.untradableItemsCount)", color: Color(white: 0.65))
            statPill(title: "STATTRAK™", value: "\(viewModel.statTrakItemsCount)", color: AppTheme.statTrakOrange)
            Spacer()
            Text("\(viewModel.filteredItems.count) shown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var portfolioValueBar: some View {
        let value = viewModel.portfolioValue

        return HStack(spacing: 10) {
            Image(systemName: "eurosign.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.Colors.csOrange)

            VStack(alignment: .leading, spacing: 1) {
                Text("MARKET VALUE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value.pricedCount > 0 ? PriceFormatter.eur(value.total) : "—")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(value.pricedCount)/\(value.totalCount) items priced")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(viewModel.priceStore.isLoading ? "Loading Steam prices…" : "Steam Market · EUR")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.06))
    }

    private var filterControlBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableCategories, id: \.self) { category in
                        let isSelected = viewModel.selectedCategory == category
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                viewModel.selectedCategory = category
                            }
                        } label: {
                            Text(category)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.orange : Color(white: 0.14))
                                )
                                .foregroundStyle(isSelected ? .black : .white)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Sort Menu
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(InventorySortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        filterChipLabel(
                            icon: "arrow.up.arrow.down",
                            text: viewModel.sortOption.rawValue,
                            isActive: viewModel.sortOption != .rarityDescending
                        )
                    }

                    // Trade Status Filter Menu
                    Menu {
                        Picker("Trade Status", selection: $viewModel.tradeFilter) {
                            ForEach(InventoryTradeFilter.allCases) { filterOption in
                                Text(filterOption.rawValue).tag(filterOption)
                            }
                        }
                    } label: {
                        filterChipLabel(
                            icon: viewModel.tradeFilter == .all ? "arrow.left.arrow.right" : "lock.shield",
                            text: viewModel.tradeFilter == .all ? "Trade Status" : viewModel.tradeFilter.rawValue,
                            isActive: viewModel.tradeFilter != .all
                        )
                    }

                    // Rarity Filter Menu
                    Menu {
                        Button("All Rarities") {
                            viewModel.selectedRarity = nil
                        }
                        Divider()
                        ForEach(SkinRarity.allCases.reversed(), id: \.self) { rarity in
                            Button(rarity.rawValue) {
                                viewModel.selectedRarity = rarity
                            }
                        }
                    } label: {
                        filterChipLabel(
                            icon: "sparkles",
                            text: viewModel.selectedRarity?.rawValue ?? "Rarity",
                            isActive: viewModel.selectedRarity != nil
                        )
                    }

                    // Exterior Filter Menu
                    Menu {
                        Button("All Exteriors") {
                            viewModel.selectedExterior = nil
                        }
                        Divider()
                        ForEach(SkinExterior.allCases, id: \.self) { exterior in
                            Button(exterior.rawValue) {
                                viewModel.selectedExterior = exterior
                            }
                        }
                    } label: {
                        filterChipLabel(
                            icon: "shield.lefthalf.filled",
                            text: viewModel.selectedExterior?.shortCode ?? viewModel.selectedExterior?.rawValue ?? "Exterior",
                            isActive: viewModel.selectedExterior != nil
                        )
                    }

                    // StatTrak Toggle
                    Button {
                        viewModel.onlyStatTrak.toggle()
                    } label: {
                        filterChipLabel(
                            icon: "number",
                            text: "StatTrak™",
                            isActive: viewModel.onlyStatTrak
                        )
                    }

                    if viewModel.hasActiveFilters {
                        Button {
                            withAnimation {
                                viewModel.resetFilters()
                            }
                        } label: {
                            Text("Reset")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(Color(white: 0.05))
    }

    private func filterChipLabel(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.orange.opacity(0.22) : Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Color.orange : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .foregroundStyle(isActive ? Color.orange : .white)
    }

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.orange)
                Text("Fetching CS2 Inventory from Steam...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.currentError, viewModel.items.isEmpty {
            errorStateView(error: error)
        } else if viewModel.filteredItems.isEmpty {
            ContentUnavailableView {
                Label("No Matching Skins", systemImage: "shippingbox")
            } description: {
                Text(
                    viewModel.items.isEmpty
                        ? "This CS2 inventory contains no items."
                        : "Try adjusting your search query or active filters."
                )
            } actions: {
                if viewModel.hasActiveFilters {
                    Button("Clear Filters") {
                        viewModel.resetFilters()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        } else {
            ScrollView {
                if isGridView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(viewModel.filteredItems) { item in
                            SkinGridCard(item: item, price: viewModel.price(for: item))
                                .onTapGesture {
                                    selectedItemForDetail = item
                                }
                        }
                    }
                    .padding(16)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredItems) { item in
                            SkinListRow(item: item, price: viewModel.price(for: item))
                                .onTapGesture {
                                    selectedItemForDetail = item
                                }
                        }
                    }
                    .padding(16)
                }
            }
            .refreshable {
                await viewModel.loadInventory(for: steamID64, forceRefresh: true)
            }
        }
    }

    private func errorStateView(error: SteamInventoryError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: iconForError(error))
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("Unable to Load Inventory")
                .font(.headline)
                .foregroundStyle(.white)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.loadInventory(for: steamID64, forceRefresh: true)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if isDeveloperModeEnabled {
                    Button {
                        isShowingDebugSheet = true
                    } label: {
                        Label("View Logs", systemImage: "terminal.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.Colors.ctBlue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForError(_ error: SteamInventoryError) -> String {
        switch error {
        case .privateInventory:
            return "lock.shield"
        case .rateLimited:
            return "hourglass.badge.plus"
        case .invalidSteamID, .profileNotFound, .badRequest:
            return "person.crop.circle.badge.exclamationmark"
        case .serverError, .networkFailure, .decodingFailure:
            return "wifi.exclamationmark"
        }
    }
}

// MARK: - Grid Card Component

private struct SkinGridCard: View {
    let item: SkinItem
    let price: PriceEntry?

    private var rarityColor: Color {
        AppTheme.rarityColor(for: item.rarity, hexOverride: item.rarityColorHex)
    }

    private var tradeBadgeColor: Color {
        AppTheme.tradeStatusColor(for: item.tradeStatus)
    }

    private var priceText: String {
        guard let price else { return "—" }
        return PriceFormatter.eur(price.displayValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if let shortExterior = item.exterior.shortCode {
                    Text(shortExterior)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.exteriorColor(for: item.exterior).opacity(0.22))
                        .foregroundStyle(AppTheme.exteriorColor(for: item.exterior))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if item.isStatTrak {
                    Text("ST™")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.statTrakOrange.opacity(0.22))
                        .foregroundStyle(AppTheme.statTrakOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if item.isSouvenir {
                    Text("SV")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.souvenirGold.opacity(0.22))
                        .foregroundStyle(AppTheme.souvenirGold)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                switch item.tradeStatus {
                case .tradable:
                    EmptyView()
                case .tradeCooldown:
                    if let badge = item.tradeStatus.badgeLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tradeBadgeColor.opacity(0.18))
                        .foregroundStyle(tradeBadgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                case .untradable:
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("UNTRADABLE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(tradeBadgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [rarityColor.opacity(item.isTradable ? 0.28 : 0.18), Color.clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 58
                        )
                    )
                    .frame(height: 95)

                AsyncImage(url: item.iconURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 88)
                            .opacity(item.isTradable ? 1.0 : 0.85)
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 3)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.weaponName ?? item.categoryType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.skinPatternName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(item.isTradable ? .white : .white.opacity(0.88))
                    .lineLimit(1)
            }

            RoundedRectangle(cornerRadius: 2)
                .fill(rarityColor)
                .frame(height: 3)

            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(priceText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(price == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.statusSuccess)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: item.isTradable ? 0.09 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            item.isOnTradeCooldown
                                ? AppTheme.Colors.csOrange.opacity(0.45)
                                : rarityColor.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - List Row Component

private struct SkinListRow: View {
    let item: SkinItem
    let price: PriceEntry?

    private var rarityColor: Color {
        AppTheme.rarityColor(for: item.rarity, hexOverride: item.rarityColorHex)
    }

    private var tradeBadgeColor: Color {
        AppTheme.tradeStatusColor(for: item.tradeStatus)
    }

    private var priceText: String {
        guard let price else { return "—" }
        return PriceFormatter.eur(price.displayValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(rarityColor)
                .frame(width: 4, height: 52)

            AsyncImage(url: item.iconURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .opacity(item.isTradable ? 1.0 : 0.85)
                } else {
                    Color(white: 0.14)
                }
            }
            .frame(width: 64, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rarityColor.opacity(0.15))
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if item.isStatTrak {
                        Text("StatTrak™")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.statTrakOrange)
                    }
                    Text(item.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isTradable ? .white : .white.opacity(0.88))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(item.rarityLocalizedName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(rarityColor)

                    if let tradeBadge = item.tradeStatus.badgeLabel {
                        HStack(spacing: 3) {
                            Image(systemName: item.isOnTradeCooldown ? "clock.fill" : "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(tradeBadge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tradeBadgeColor.opacity(0.16))
                        .foregroundStyle(tradeBadgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if let collection = item.collectionName {
                        Text("• \(collection)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(priceText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(price == nil ? AppTheme.Colors.textSecondary : .white)

                if let shortCode = item.exterior.shortCode {
                    Text(shortCode)
                        .font(.caption.weight(.bold).monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.exteriorColor(for: item.exterior).opacity(0.2))
                        .foregroundStyle(AppTheme.exteriorColor(for: item.exterior))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: item.isTradable ? 0.09 : 0.07))
        )
    }
}

// MARK: - Detail Inspection Sheet

private struct SkinDetailSheet: View {
    let item: SkinItem
    let price: PriceEntry?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDeveloperModeEnabled") private var isDeveloperModeEnabled: Bool = false
    @State private var isShowingMarketSheet: Bool = false

    private var rarityColor: Color {
        AppTheme.rarityColor(for: item.rarity, hexOverride: item.rarityColorHex)
    }

    private var marketURL: URL? {
        let hash = item.marketHashName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://steamcommunity.com/market/listings/730/\(hash)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [rarityColor.opacity(0.35), .clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 110
                                )
                            )
                            .frame(height: 180)

                        AsyncImage(url: item.iconURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 150)
                            } else {
                                ProgressView()
                            }
                        }
                    }

                    VStack(spacing: 6) {
                        Text(item.fullName)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        if let collection = item.collectionName {
                            Text(collection)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    WearTierBar(exterior: item.exterior)

                    VStack(spacing: 12) {
                        detailRow(label: "Rarity", value: item.rarityLocalizedName, valueColor: rarityColor)
                        detailRow(
                            label: "Exterior",
                            value: item.exterior.rawValue,
                            valueColor: AppTheme.exteriorColor(for: item.exterior)
                        )
                        detailRow(label: "Category", value: item.categoryType)
                        detailRow(
                            label: "Trade Status",
                            value: item.tradeStatus.detailedDescription,
                            valueColor: AppTheme.tradeStatusColor(for: item.tradeStatus)
                        )

                        detailRow(
                            label: "Steam Price (min)",
                            value: price.map { PriceFormatter.eur($0.lowest) } ?? "—",
                            valueColor: price == nil ? AppTheme.Colors.textSecondary : .white,
                            isMonospaced: price != nil
                        )
                        detailRow(
                            label: "Steam Price (median)",
                            value: price?.median.map { PriceFormatter.eur($0) } ?? "—",
                            valueColor: price?.median == nil ? AppTheme.Colors.textSecondary : .white,
                            isMonospaced: price?.median != nil
                        )

                        Button {
                            isShowingMarketSheet = true
                        } label: {
                            HStack(alignment: .top) {
                                Text("Community Market")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(item.isMarketable ? "Marketable" : "Not Marketable")
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(item.isMarketable ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(marketURL == nil)

                        if isDeveloperModeEnabled {
                            detailRow(label: "Asset ID", value: item.assetId, isMonospaced: true)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.1))
                    )

                    Text("Steam Community Market prices in EUR — lowest listing and median sale price.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .sheet(isPresented: $isShowingMarketSheet) {
            if let url = marketURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailRow(
        label: String,
        value: String,
        valueColor: Color = .white,
        isMonospaced: Bool = false
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(isMonospaced ? .footnote.monospaced() : .subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Wear Tier Bar (FN / MW / FT / WW / BS)

private struct WearTierBar: View {
    let exterior: SkinExterior

    private static let order: [SkinExterior] = [
        .factoryNew, .minimalWear, .fieldTested, .wellWorn, .battleScarred
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 2) {
                ForEach(Self.order, id: \.rawValue) { tier in
                    Rectangle()
                        .fill(
                            tier == exterior
                                ? AppTheme.exteriorColor(for: tier)
                                : AppTheme.exteriorColor(for: tier).opacity(0.22)
                        )
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 0) {
                ForEach(Self.order, id: \.rawValue) { tier in
                    Text(tier.shortCode ?? "")
                        .font(.system(size: 9, weight: tier == exterior ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(tier == exterior ? AppTheme.exteriorColor(for: tier) : AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}