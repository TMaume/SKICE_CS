import Foundation
import Observation

/// Sorting criteria for the user's CS2 inventory.
public enum InventorySortOption: String, CaseIterable, Identifiable, Sendable {
    case rarityDescending = "Rarity (High to Low)"
    case rarityAscending = "Rarity (Low to High)"
    case nameAscending = "Name (A–Z)"
    case exteriorBestFirst = "Exterior (FN to BS)"

    public var id: String { rawValue }
}

/// Filter options for trade availability status. Defaults to `.all`.
public enum InventoryTradeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Items"
    case tradableOnly = "Tradable"
    case tradeCooldownOnly = "On Cooldown"
    case untradableOnly = "Not Tradable"

    public var id: String { rawValue }
}

/// Manages loading state, filtering, and search for the CS2 Inventory module.
@Observable
@MainActor
public final class InventoryViewModel {
    // MARK: - State Properties

    public private(set) var items: [SkinItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var currentError: SteamInventoryError?
    public private(set) var lastLoadedSteamID: String?

    // MARK: - Search & Filter Controls

    public var searchText: String = ""
    public var selectedCategory: String = "All"
    public var selectedRarity: SkinRarity?
    public var selectedExterior: SkinExterior?
    public var onlyStatTrak: Bool = false
    public var tradeFilter: InventoryTradeFilter = .all
    public var sortOption: InventorySortOption = .rarityDescending

    // MARK: - Dependencies

    private let service: SteamInventoryServicing

    public init(service: SteamInventoryServicing = SteamInventoryService()) {
        self.service = service
    }

    // MARK: - Computed Properties

    /// Dynamic list of item categories present in the loaded inventory.
    public var availableCategories: [String] {
        let unique = Set(items.map(\.categoryType)).sorted()
        return ["All"] + unique
    }

    /// Filtered and sorted items matching the active search query and filter pills.
    public var filteredItems: [SkinItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = items.filter { item in
            if selectedCategory != "All" && item.categoryType != selectedCategory {
                return false
            }
            if let selectedRarity, item.rarity != selectedRarity {
                return false
            }
            if let selectedExterior, item.exterior != selectedExterior {
                return false
            }
            if onlyStatTrak && !item.isStatTrak {
                return false
            }
            switch tradeFilter {
            case .all:
                break
            case .tradableOnly:
                if !item.isTradable { return false }
            case .tradeCooldownOnly:
                if !item.isOnTradeCooldown { return false }
            case .untradableOnly:
                if !item.isPermanentlyUntradable { return false }
            }
            if !query.isEmpty {
                let matchesName = item.fullName.lowercased().contains(query)
                let matchesCollection = item.collectionName?.lowercased().contains(query) ?? false
                let matchesRarity = item.rarityLocalizedName.lowercased().contains(query)
                let matchesTrade = item.tradeStatus.detailedDescription.lowercased().contains(query)
                if !matchesName && !matchesCollection && !matchesRarity && !matchesTrade {
                    return false
                }
            }
            return true
        }

        return sortItems(filtered, by: sortOption)
    }

    public var totalItemsCount: Int {
        items.count
    }

    public var tradableItemsCount: Int {
        items.filter(\.isTradable).count
    }

    public var cooldownItemsCount: Int {
        items.filter(\.isOnTradeCooldown).count
    }

    public var untradableItemsCount: Int {
        items.filter(\.isPermanentlyUntradable).count
    }

    public var statTrakItemsCount: Int {
        items.filter(\.isStatTrak).count
    }

    public var hasActiveFilters: Bool {
        selectedCategory != "All"
            || selectedRarity != nil
            || selectedExterior != nil
            || onlyStatTrak
            || tradeFilter != .all
            || !searchText.isEmpty
    }

    // MARK: - Actions

    /// Fetches the public CS2 inventory for the specified `steamID64`.
    public func loadInventory(for steamID64: String, forceRefresh: Bool = false) async {
        let trimmed = steamID64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.currentError = .invalidSteamID("Empty")
            return
        }

        if !forceRefresh, lastLoadedSteamID == trimmed, !items.isEmpty {
            return
        }

        isLoading = true
        currentError = nil

        do {
            let fetchedItems = try await service.fetchInventory(for: trimmed)
            self.items = fetchedItems
            self.lastLoadedSteamID = trimmed
        } catch let inventoryError as SteamInventoryError {
            self.currentError = inventoryError
        } catch {
            self.currentError = .networkFailure(error.localizedDescription)
        }

        isLoading = false
    }

    /// Resets all active search and category filters.
    public func resetFilters() {
        searchText = ""
        selectedCategory = "All"
        selectedRarity = nil
        selectedExterior = nil
        onlyStatTrak = false
        tradeFilter = .all
        sortOption = .rarityDescending
    }

    // MARK: - Sorting Helper

    private func sortItems(_ list: [SkinItem], by option: InventorySortOption) -> [SkinItem] {
        switch option {
        case .rarityDescending:
            return list.sorted { lhs, rhs in
                if lhs.rarity != rhs.rarity {
                    return lhs.rarity > rhs.rarity
                }
                return lhs.fullName < rhs.fullName
            }
        case .rarityAscending:
            return list.sorted { lhs, rhs in
                if lhs.rarity != rhs.rarity {
                    return lhs.rarity < rhs.rarity
                }
                return lhs.fullName < rhs.fullName
            }
        case .nameAscending:
            return list.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        case .exteriorBestFirst:
            let order: [SkinExterior] = [.factoryNew, .minimalWear, .fieldTested, .wellWorn, .battleScarred, .notPainted]
            return list.sorted { lhs, rhs in
                let leftIndex = order.firstIndex(of: lhs.exterior) ?? order.count
                let rightIndex = order.firstIndex(of: rhs.exterior) ?? order.count
                if leftIndex != rightIndex {
                    return leftIndex < rightIndex
                }
                return lhs.rarity > rhs.rarity
            }
        }
    }
}