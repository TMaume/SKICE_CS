import SwiftUI

/// Trade-Up Contract calculator. Select 10 items of a single rarity, then view
/// every probable outcome (sorted by probability), the expected value (EV) and
/// ROI in EUR using Steam Market prices.
public struct TradeUpCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TradeUpCalculatorViewModel

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 10)
    ]

    public init(
        inventory: [SkinItem],
        priceStore: PriceStore
    ) {
        self._viewModel = State(
            initialValue: TradeUpCalculatorViewModel(inventory: inventory, inputPriceStore: priceStore)
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.oledBlack.ignoresSafeArea()

                if viewModel.eligibleItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            rarityPicker
                            selectionHeader
                            itemGrid
                            if viewModel.canEvaluate {
                                if let notice = viewModel.notice {
                                    noticeBanner(notice)
                                }
                                resultsSection
                            } else if let error = viewModel.lastError {
                                errorBanner(error)
                            }
                            disclaimer
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Trade-Up Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

    // MARK: - Rarity picker

    private var rarityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INPUT RARITY")
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableRarities, id: \.self) { rarity in
                        let isSelected = viewModel.selectedRarity == rarity
                        let count = viewModel.items(for: rarity).count
                        Button {
                            viewModel.selectedRarity = rarity
                        } label: {
                            VStack(spacing: 2) {
                                Text(rarity.rawValue)
                                    .font(.caption.weight(.semibold))
                                Text("\(count) available")
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(isSelected ? AppTheme.Colors.csOrange : Color(white: 0.13))
                            )
                            .foregroundStyle(isSelected ? .black : .white)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Selection header

    private var selectionHeader: some View {
        HStack {
            if let label = viewModel.tradeUpLabel {
                Text(label)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Text("\(viewModel.selectedItems.count) / \(TradeUpEngine.contractSize) selected")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    viewModel.canEvaluate ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textPrimary
                )

            if !viewModel.selectedItems.isEmpty {
                Button("Clear") {
                    viewModel.clearSelection()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.statusDanger)
            }
        }
    }

    // MARK: - Item grid

    private var itemGrid: some View {
        let rarity = viewModel.selectedRarity
        let items = rarity.map { viewModel.items(for: $0) } ?? []

        return Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Eligible Items", systemImage: "shippingbox")
                } description: {
                    Text("No items of this rarity are in the local trade-up catalog.")
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(items) { item in
                        TradeUpInputCard(
                            item: item,
                            isSelected: viewModel.isSelected(item),
                            price: viewModel.inputPrice(for: item)
                        ) {
                            viewModel.toggleSelection(item)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 12) {
            valuationSummary

            Text("PROBABLE OUTCOMES")
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.outcomes) { outcome in
                TradeUpOutcomeRow(
                    outcome: outcome,
                    price: viewModel.outcomePrices[outcome.marketHashName]
                )
            }
        }
    }

    private var valuationSummary: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INPUT COST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(PriceFormatter.eur(viewModel.inputCost))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("EXPECTED VALUE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.expectedValue.map(PriceFormatter.eur) ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.statusSuccess)
                }
            }

            HStack {
                if let roi = viewModel.roiPercent {
                    Text(roi >= 0 ? "ROI \(String(format: "+%.1f%%", roi))" : "ROI \(String(format: "%.1f%%", roi))")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(roi >= 0 ? AppTheme.Colors.statusSuccess : AppTheme.Colors.statusDanger)
                } else {
                    Text("ROI —")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                if viewModel.isLoadingPrices {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.orange)
                    Text("Pricing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Colors.csOrange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Colors.csOrange)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.Colors.csOrange.opacity(0.12))
        )
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.Colors.ctBlue)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.Colors.ctBlue.opacity(0.12))
        )
    }

    private var disclaimer: some View {
        Text("Simulation indicative — Steam Market prices in EUR (median ?? lowest listing).")
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Trade-Up Items", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("None of your inventory items are eligible for a trade-up contract with the local catalog.")
        }
    }
}

// MARK: - Input card

private struct TradeUpInputCard: View {
    let item: SkinItem
    let isSelected: Bool
    let price: PriceEntry?
    let onTap: () -> Void

    private var rarityColor: Color {
        AppTheme.rarityColor(for: item.rarity, hexOverride: item.rarityColorHex)
    }

    private var priceText: String {
        guard let price else { return "—" }
        return PriceFormatter.eur(price.displayValue)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if let short = item.exterior.shortCode {
                        Text(short)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppTheme.exteriorColor(for: item.exterior).opacity(0.22))
                            .foregroundStyle(AppTheme.exteriorColor(for: item.exterior))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if item.isStatTrak {
                        Text("ST™")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppTheme.statTrakOrange.opacity(0.22))
                            .foregroundStyle(AppTheme.statTrakOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(rarityColor.opacity(0.12))
                    AsyncImage(url: item.iconURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(4)
                }
                .frame(height: 58)
                .frame(maxWidth: .infinity)

                Text(item.weaponName ?? item.categoryType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.skinPatternName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let collection = item.collectionName {
                    Text(collection)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                RoundedRectangle(cornerRadius: 2)
                    .fill(rarityColor)
                    .frame(height: 3)

                HStack(spacing: 3) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(priceText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(price == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.statusSuccess)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: isSelected ? 0.14 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? AppTheme.Colors.statusSuccess.opacity(0.6) : rarityColor.opacity(0.3),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Outcome row

private struct TradeUpOutcomeRow: View {
    let outcome: TradeUpOutcome
    let price: PriceEntry?

    private var rarityColor: Color {
        AppTheme.rarityColor(for: outcome.item.rarity)
    }

    private var exterior: SkinExterior {
        SkinExterior.forFloat(outcome.outputFloat)
    }

    private var priceText: String {
        guard let price else { return "—" }
        return PriceFormatter.eur(price.displayValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(rarityColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if outcome.isStatTrak {
                        Text("StatTrak™")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.statTrakOrange)
                    }
                    Text(outcome.item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(outcome.collection.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let code = exterior.shortCode {
                        Text("· \(code)")
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(AppTheme.exteriorColor(for: exterior))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(outcome.probabilityPercent)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.csOrange)
                Text(priceText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(price == nil ? AppTheme.Colors.textSecondary : .white)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
        )
    }
}
