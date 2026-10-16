import SwiftUI

/// Main CS2 Inventory screen supporting Grid/List toggles, rarity colors, verified trade-lock / untradable badges, and conditional debug access.
public struct InventoryView: View {
    public let steamID64: String
    let authSession: SteamAuthSession

    @AppStorage("isDeveloperModeEnabled") private var isDeveloperModeEnabled: Bool = false

    @State private var viewModel: InventoryViewModel
    @State private var isGridView: Bool = true
    @State private var selectedItemForDetail: SkinItem?
    @State private var isShowingDebugSheet: Bool = false
    @State private var isShowingTradeUpCalculator: Bool = false
    @State private var isShowingFilters: Bool = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 155, maximum: 210), spacing: 12)
    ]

    public init(
        steamID64: String,
        authSession: SteamAuthSession,
        viewModel: InventoryViewModel = InventoryViewModel()
    ) {
        self.steamID64 = steamID64
        self.authSession = authSession
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            AppTheme.Colors.oledBlack.ignoresSafeArea()

            contentArea
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppTheme.Colors.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
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
        .sheet(isPresented: $isShowingFilters) {
            InventoryFilterSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedItemForDetail) { item in
            SkinDetailSheet(item: item, price: viewModel.price(for: item), inspection: viewModel.inspection(for: item))
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
            await viewModel.loadInspections(authSession: authSession)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    /// Single-row compact summary (item counts + market value + filter entry).
    /// Lives inside the scrollable content so it scrolls away with the grid.
    private var compactSummaryBar: some View {
        let value = viewModel.portfolioValue

        return HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.Colors.csOrange)

            Text("\(viewModel.totalItemsCount)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("\(viewModel.tradableItemsCount) tradable")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            if viewModel.statTrakItemsCount > 0 {
                Text("\(viewModel.statTrakItemsCount) ST™")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.statTrakOrange)
            }

            Spacer()

            Text(value.pricedCount > 0 ? PriceFormatter.eur(value.total) : "—")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Colors.csOrange)

            Button {
                isShowingFilters = true
            } label: {
                Image(systemName: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.hasActiveFilters ? AppTheme.Colors.csOrange : AppTheme.Colors.textSecondary)
            }
            .accessibilityLabel("Filters")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(AppTheme.Colors.borderSubtle, lineWidth: 1)
                )
        )
    }

    /// Entry point to the Trade-Up Contract calculator, placed directly under
    /// the inventory summary so it reads as part of the same header group.
    private var tradeUpButton: some View {
        Button {
            isShowingTradeUpCalculator = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.csOrange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Trade-Up Contract")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Simulate EV / ROI in EUR")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(AppTheme.Colors.csOrange.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Trade-Up Calculator")
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
                VStack(spacing: 12) {
                    if !viewModel.items.isEmpty {
                        compactSummaryBar
                        tradeUpButton
                    }

                    if isGridView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(viewModel.filteredItems) { item in
                                SkinGridCard(item: item, price: viewModel.price(for: item), inspection: viewModel.inspection(for: item))
                                    .onTapGesture {
                                        selectedItemForDetail = item
                                    }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.filteredItems) { item in
                                SkinListRow(item: item, price: viewModel.price(for: item), inspection: viewModel.inspection(for: item))
                                    .onTapGesture {
                                        selectedItemForDetail = item
                                    }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                await viewModel.loadInventory(for: steamID64, forceRefresh: true)
                await viewModel.loadInspections(authSession: authSession, forceRefresh: true)
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
    let inspection: GCItemInspection?

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

            if let wear = inspection?.wearText {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(wear)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(AppTheme.Colors.ctBlue)
            }
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
    let inspection: GCItemInspection?

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

                    if let wear = inspection?.wearText {
                        Text(wear)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppTheme.Colors.ctBlue)
                    }

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
    let inspection: GCItemInspection?
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

                        if let inspection {
                            detailRow(
                                label: "Float",
                                value: inspection.wearText ?? "—",
                                valueColor: AppTheme.Colors.ctBlue,
                                isMonospaced: true
                            )
                            detailRow(
                                label: "Pattern Seed",
                                value: inspection.paintSeed.map { "#\($0)" } ?? "—",
                                isMonospaced: inspection.paintSeed != nil
                            )
                            if inspection.isStatTrak, let kills = inspection.killEaterValue {
                                detailRow(
                                    label: "StatTrak Kills",
                                    value: "\(kills)",
                                    valueColor: AppTheme.statTrakOrange,
                                    isMonospaced: true
                                )
                            }
                            detailRow(
                                label: "Stickers",
                                value: inspection.hasStickers ? "\(inspection.stickers.count)" : "None",
                                valueColor: inspection.hasStickers ? AppTheme.Colors.csOrange : AppTheme.Colors.textSecondary
                            )
                        }
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

                    PriceHistorySection(marketHashName: item.marketHashName)

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
// MARK: - Filters Sheet

private struct InventoryFilterSheet: View {
    let viewModel: InventoryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.oledBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        categorySection
                        raritySection
                        exteriorSection
                        tradeStatusSection
                        statTrakSection
                        sortSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.hasActiveFilters {
                        Button("Reset") {
                            viewModel.resetFilters()
                        }
                        .foregroundStyle(AppTheme.Colors.statusDanger)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Colors.csOrange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var categorySection: some View {
        sectionCard("Category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableCategories, id: \.self) { category in
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
                                    Capsule().fill(viewModel.selectedCategory == category ? AppTheme.Colors.csOrange : Color(white: 0.14))
                                )
                                .foregroundStyle(viewModel.selectedCategory == category ? .black : .white)
                        }
                    }
                }
            }
        }
    }

    private var raritySection: some View {
        sectionCard("Rarity") {
            Menu {
                Button("All Rarities") { viewModel.selectedRarity = nil }
                Divider()
                ForEach(SkinRarity.allCases.reversed(), id: \.self) { rarity in
                    Button(rarity.rawValue) { viewModel.selectedRarity = rarity }
                }
            } label: {
                menuValueRow(
                    icon: "sparkles",
                    value: viewModel.selectedRarity?.rawValue ?? "All",
                    isActive: viewModel.selectedRarity != nil
                )
            }
        }
    }

    private var exteriorSection: some View {
        sectionCard("Exterior") {
            Menu {
                Button("All Exteriors") { viewModel.selectedExterior = nil }
                Divider()
                ForEach(SkinExterior.allCases, id: \.self) { exterior in
                    Button(exterior.rawValue) { viewModel.selectedExterior = exterior }
                }
            } label: {
                menuValueRow(
                    icon: "shield.lefthalf.filled",
                    value: viewModel.selectedExterior?.shortCode ?? viewModel.selectedExterior?.rawValue ?? "All",
                    isActive: viewModel.selectedExterior != nil
                )
            }
        }
    }

    private var tradeStatusSection: some View {
        sectionCard("Trade Status") {
            Menu {
                ForEach(InventoryTradeFilter.allCases) { filter in
                    Button(filter.rawValue) { viewModel.tradeFilter = filter }
                }
            } label: {
                menuValueRow(
                    icon: viewModel.tradeFilter == .all ? "arrow.left.arrow.right" : "lock.shield",
                    value: viewModel.tradeFilter.rawValue,
                    isActive: viewModel.tradeFilter != .all
                )
            }
        }
    }

    private var statTrakSection: some View {
        sectionCard("StatTrak™") {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.onlyStatTrak.toggle()
                }
            } label: {
                HStack {
                    Label("StatTrak™ only", systemImage: "number")
                        .foregroundStyle(viewModel.onlyStatTrak ? AppTheme.statTrakOrange : .white)
                    Spacer()
                    Image(systemName: viewModel.onlyStatTrak ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.onlyStatTrak ? AppTheme.statTrakOrange : AppTheme.Colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var sortSection: some View {
        sectionCard("Sort") {
            Menu {
                ForEach(InventorySortOption.allCases) { option in
                    Button(option.rawValue) { viewModel.sortOption = option }
                }
            } label: {
                menuValueRow(
                    icon: "arrow.up.arrow.down",
                    value: viewModel.sortOption.rawValue,
                    isActive: viewModel.sortOption != .rarityDescending
                )
            }
        }
    }

    // MARK: Helpers

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.07))
        )
    }

    private func menuValueRow(icon: String, value: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? AppTheme.Colors.csOrange : AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? AppTheme.Colors.csOrange : .white)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .contentShape(Rectangle())
    }
}
