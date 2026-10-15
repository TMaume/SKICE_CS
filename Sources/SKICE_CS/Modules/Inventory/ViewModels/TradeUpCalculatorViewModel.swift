import Foundation
import Observation

/// Observable controller for the Trade-Up Contract calculator.
/// Selection lives here (max 10 items, single rarity), the deterministic engine
/// produces outcomes, and Steam Market prices (EUR) drive EV / ROI.
@Observable
@MainActor
public final class TradeUpCalculatorViewModel {

    // MARK: - State

    /// Inventory items eligible as trade-up inputs (collection in catalog, R+1 exists).
    public private(set) var eligibleItems: [SkinItem]

    /// Currently chosen input rarity; changing it clears the selection.
    public var selectedRarity: SkinRarity? = nil {
        didSet {
            if oldValue != selectedRarity {
                selectedItems = []
                refreshOutcomes()
            }
        }
    }

    public private(set) var selectedItems: [SkinItem] = []
    public private(set) var evaluation: TradeUpEvaluation?
    public private(set) var outcomes: [TradeUpOutcome] = []
    public private(set) var outcomePrices: [String: PriceEntry] = [:]
    public private(set) var isLoadingPrices = false
    public private(set) var lastError: String?
    public private(set) var notice: String?

    // MARK: - Dependencies

    private let inputPriceStore: PriceStore
    private let priceService: PriceService

    public init(
        inventory: [SkinItem],
        inputPriceStore: PriceStore,
        priceService: PriceService = .shared
    ) {
        self.eligibleItems = inventory.filter { TradeUpEngine.isEligible($0) }
        self.inputPriceStore = inputPriceStore
        self.priceService = priceService
        if let first = self.availableRarities.first {
            self.selectedRarity = first
        }
    }

    // MARK: - Available rarities

    /// Rarities present among eligible items, sorted lowest-grade first.
    public var availableRarities: [SkinRarity] {
        var seen = Set<SkinRarity>()
        var order: [SkinRarity] = []
        for item in eligibleItems {
            guard !seen.contains(item.rarity) else { continue }
            seen.insert(item.rarity)
            order.append(item.rarity)
        }
        return order.sorted { $0.sortRank < $1.sortRank }
    }

    /// Eligible items of the given rarity.
    public func items(for rarity: SkinRarity) -> [SkinItem] {
        eligibleItems.filter { $0.rarity == rarity }
    }

    // MARK: - Selection

    public var canEvaluate: Bool {
        selectedItems.count == TradeUpEngine.contractSize
    }

    public func isSelected(_ item: SkinItem) -> Bool {
        selectedItems.contains { $0.id == item.id }
    }

    public func toggleSelection(_ item: SkinItem) {
        if let index = selectedItems.firstIndex(where: { $0.id == item.id }) {
            selectedItems.remove(at: index)
        } else {
            guard selectedItems.count < TradeUpEngine.contractSize else { return }
            selectedItems.append(item)
        }
        refreshOutcomes()
    }

    public func clearSelection() {
        selectedItems = []
        refreshOutcomes()
    }

    // MARK: - Evaluation

    /// Runs the engine synchronously; kicks off async outcome pricing when complete.
    private func refreshOutcomes() {
        outcomes = []
        outcomePrices = [:]
        evaluation = nil
        notice = nil
        lastError = nil
        guard canEvaluate else { return }

        let inputs = selectedItems.map(TradeUpInput.init(item:))
        let eval: TradeUpEvaluation
        do {
            eval = try TradeUpEngine.evaluate(inputs)
        } catch {
            lastError = error.localizedDescription
            return
        }

        evaluation = eval
        outcomes = eval.outcomes

        if !eval.isFullyResolved {
            let names = eval.unresolvedCollections.joined(separator: ", ")
            notice = eval.hasOutcomes
                ? "Partial data: \(names) not in the local catalog (excluded from EV)."
                : "Output pool for \(names) is not in the local catalog — showing input cost only."
        }

        guard eval.hasOutcomes else { return }
        Task { await loadOutcomePrices() }
    }

    private func loadOutcomePrices() async {
        let hashes = Set(outcomes.map(\.marketHashName))
        guard !hashes.isEmpty else { return }

        isLoadingPrices = true
        defer { isLoadingPrices = false }

        do {
            let table = try await priceService.loadPriceTable(for: hashes)
            var dict: [String: PriceEntry] = [:]
            for hash in hashes {
                if let entry = table.entry(for: hash) {
                    dict[hash] = entry
                }
            }
            outcomePrices = dict
        } catch {
            // Leave outcomePrices empty — valuation becomes unavailable but outcomes remain.
        }
    }

    /// Steam Market price for an eligible input item (median ?? lowest), if priced.
    public func inputPrice(for item: SkinItem) -> PriceEntry? {
        inputPriceStore.entry(for: item)
    }

    // MARK: - Valuation

    /// Total Steam Market cost (EUR) of the 10 selected inputs (median ?? lowest).
    public var inputCost: Decimal {
        selectedItems.reduce(Decimal.zero) { partial, item in
            partial + (inputPriceStore.entry(for: item)?.displayValue ?? 0)
        }
    }

    /// Probability-weighted expected value of the outcome in EUR.
    public var expectedValue: Decimal? {
        guard !outcomes.isEmpty else { return nil }
        var total = Decimal.zero
        var anyPriced = false
        for outcome in outcomes {
            guard let price = outcomePrices[outcome.marketHashName]?.displayValue else { continue }
            let probability = NSDecimalNumber(value: outcome.probability).decimalValue
            total += price * probability
            anyPriced = true
        }
        return anyPriced ? total : nil
    }

    /// ROI percentage = (EV − cost) / cost × 100.
    public var roiPercent: Double? {
        guard let ev = expectedValue, inputCost > 0 else { return nil }
        let roi = (ev - inputCost) / inputCost * 100
        return NSDecimalNumber(decimal: roi).doubleValue
    }

    /// A short "input rarity → output rarity" label for the header.
    public var tradeUpLabel: String? {
        guard let rarity = selectedRarity, let next = rarity.nextTradeUpRarity else { return nil }
        return "\(rarity.rawValue) → \(next.rawValue)"
    }
}
