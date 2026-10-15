import Foundation
import Observation

/// Aggregate Steam Market value of a set of items.
public struct PortfolioValue: Sendable, Equatable {
    public let total: Decimal
    public let pricedCount: Int
    public let totalCount: Int

    public static let empty = PortfolioValue(total: 0, pricedCount: 0, totalCount: 0)

    public init(total: Decimal, pricedCount: Int, totalCount: Int) {
        self.total = total
        self.pricedCount = pricedCount
        self.totalCount = totalCount
    }
}

/// Observable holder of the Steam Market price table for the loaded inventory.
/// Owns loading state so both views and the view model can read prices reactively.
@Observable
@MainActor
public final class PriceStore {
    public private(set) var table: PriceTable = .empty
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    private let service: PriceService

    public init(service: PriceService = .shared) {
        self.service = service
    }

    /// Loads (or refreshes, once stale) prices for the given inventory items.
    public func loadPrices(for items: [SkinItem], forceRefresh: Bool = false) async {
        let hashes = Set(items.map(\.marketHashName).filter { !$0.isEmpty })
        guard !hashes.isEmpty else { return }

        if !forceRefresh, table.covers(hashes), !table.isStale { return }

        // Re-entrancy guard: a .task and a pull-to-refresh can both fire.
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            table = try await service.loadPriceTable(for: hashes, forceRefresh: forceRefresh)
            lastError = nil
        } catch is CancellationError {
            // Torn-down view; leave cached state untouched.
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func entry(for item: SkinItem) -> PriceEntry? {
        table.entry(for: item.marketHashName)
    }

    /// Sums each priced item's representative value (median, else lowest) × amount.
    public func portfolioValue(for items: [SkinItem]) -> PortfolioValue {
        var total: Decimal = 0
        var priced = 0
        for item in items {
            guard let entry = table.entry(for: item.marketHashName) else { continue }
            priced += 1
            total += entry.displayValue * Decimal(max(item.amount, 1))
        }
        return PortfolioValue(total: total, pricedCount: priced, totalCount: items.count)
    }
}
