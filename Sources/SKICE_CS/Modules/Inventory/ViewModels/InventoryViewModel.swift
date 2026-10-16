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

    /// Game Coordinator inspections (float / seed / stickers), keyed by asset id.
    public private(set) var inspections: [String: GCItemInspection] = [:]
    /// True while a fresh Game Coordinator read is in flight.
    public private(set) var isFetchingInspections: Bool = false
    /// Last inspection read error, if any.
    public private(set) var inspectionError: String?

    // MARK: - Search & Filter Controls

    public var searchText: String = "" { didSet { recomputeDerivedState() } }
    public var selectedCategory: String = "All" { didSet { recomputeDerivedState() } }
    public var selectedRarity: SkinRarity? { didSet { recomputeDerivedState() } }
    public var selectedExterior: SkinExterior? { didSet { recomputeDerivedState() } }
    public var onlyStatTrak: Bool = false { didSet { recomputeDerivedState() } }
    public var tradeFilter: InventoryTradeFilter = .all { didSet { recomputeDerivedState() } }
    public var sortOption: InventorySortOption = .rarityDescending { didSet { recomputeDerivedState() } }

    // MARK: - Dependencies

    private let service: SteamInventoryServicing
    private let inspectionStore: ItemInspectionStore
    private let gcClient: GameCoordinatorClient

    /// Shared Steam Market price store for the items in this inventory.
    public let priceStore: PriceStore

    public init(
        service: SteamInventoryServicing = SteamInventoryService(),
        priceStore: PriceStore = PriceStore(),
        inspectionStore: ItemInspectionStore = .shared,
        gcClient: GameCoordinatorClient = .shared
    ) {
        self.service = service
        self.priceStore = priceStore
        self.inspectionStore = inspectionStore
        self.gcClient = gcClient
    }

    // MARK: - Cached Derived State

    /// Dynamic list of item categories present in the loaded inventory.
    public private(set) var availableCategories: [String] = ["All"]

    /// Filtered and sorted items matching the active search query and filter pills.
    /// Recomputed once per mutation, not on every body evaluation.
    public private(set) var filteredItems: [SkinItem] = []

    public private(set) var tradableItemsCount: Int = 0
    public private(set) var cooldownItemsCount: Int = 0
    public private(set) var untradableItemsCount: Int = 0
    public private(set) var statTrakItemsCount: Int = 0

    public var totalItemsCount: Int {
        items.count
    }

    public var hasActiveFilters: Bool {
        selectedCategory != "All"
            || selectedRarity != nil
            || selectedExterior != nil
            || onlyStatTrak
            || tradeFilter != .all
            || !searchText.isEmpty
    }

    /// Recomputes the cached filtered list and counters. Called after any change
    /// to `items`, search text, or a filter/sort control.
    private func recomputeDerivedState() {
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

        filteredItems = sortItems(filtered, by: sortOption)

        tradableItemsCount = items.filter(\.isTradable).count
        cooldownItemsCount = items.filter(\.isOnTradeCooldown).count
        untradableItemsCount = items.filter(\.isPermanentlyUntradable).count
        statTrakItemsCount = items.filter(\.isStatTrak).count

        let unique = Set(items.map(\.categoryType)).sorted()
        availableCategories = ["All"] + unique
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

        // Render the cached inventory immediately while the network refresh runs.
        if !forceRefresh, items.isEmpty, let cached = Self.loadCachedItems(for: trimmed) {
            items = cached
            lastLoadedSteamID = trimmed
            recomputeDerivedState()
        }

        isLoading = true
        currentError = nil

        do {
            let fetchedItems = try await service.fetchInventory(for: trimmed)
            self.items = fetchedItems
            self.lastLoadedSteamID = trimmed
            Self.saveCachedItems(fetchedItems, for: trimmed)
            recomputeDerivedState()
        } catch let inventoryError as SteamInventoryError {
            self.currentError = inventoryError
        } catch {
            self.currentError = .networkFailure(error.localizedDescription)
        }

        isLoading = false

        // Prices load separately (cached ~24h) so the inventory renders first.
        // Run in an unstructured Task: a pull-to-refresh teardown or tab switch
        // cancels THIS (.task/.refreshable) task, which must not kill the price
        // fetch mid-flight.
        if !items.isEmpty {
            let snapshot = items
            let store = priceStore
            Task { await store.loadPrices(for: snapshot) }
        }
    }

    // MARK: - Game Coordinator inspections (float / seed / stickers)

    /// GC inspection for an item (exact float, pattern seed, stickers), or nil.
    public func inspection(for item: SkinItem) -> GCItemInspection? {
        inspections[item.assetId]
    }

    /// Loads item inspections: instantly from the on-device cache, then a fresh
    /// read from the Game Coordinator when a signed-in Tier B session exists.
    /// The public Web API cannot provide float, so this needs the GC session.
    public func loadInspections(authSession: SteamAuthSession, forceRefresh: Bool = false) async {
        if inspections.isEmpty || forceRefresh {
            inspections = inspectionStore.all()
        }

        guard let credentials = authSession.gameCoordinatorCredentials(),
              let steamID = UInt64(credentials.steamID64) else {
            return
        }
        guard !isFetchingInspections else { return }

        isFetchingInspections = true
        inspectionError = nil
        defer { isFetchingInspections = false }

        do {
            let fetched = try await gcClient.fetchItemInspections(
                steamID64: steamID,
                refreshToken: credentials.refreshToken
            )
            inspectionStore.merge(fetched)
            inspections = inspectionStore.all()
            DebugLogger.shared.info(
                "Inventory inspections: fetched \(fetched.count), cached \(inspections.count)",
                category: "Inventory"
            )
        } catch {
            inspectionError = error.localizedDescription
        }
    }

    // MARK: - Pricing

    /// Steam Market price for an item, or nil when unpriced (shown as "—").
    public func price(for item: SkinItem) -> PriceEntry? {
        priceStore.entry(for: item)
    }

    /// Aggregate Steam Market value of the current inventory.
    public var portfolioValue: PortfolioValue {
        priceStore.portfolioValue(for: items)
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

    // MARK: - Local inventory cache

    private static func inventoryCacheKey(_ steamID64: String) -> String {
        "com.dtl21.SKICEcs.cachedInventory.v1." + steamID64
    }

    private static func saveCachedItems(_ items: [SkinItem], for steamID64: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: inventoryCacheKey(steamID64))
    }

    private static func loadCachedItems(for steamID64: String) -> [SkinItem]? {
        guard let data = UserDefaults.standard.data(forKey: inventoryCacheKey(steamID64)) else { return nil }
        return try? JSONDecoder().decode([SkinItem].self, from: data)
    }
}