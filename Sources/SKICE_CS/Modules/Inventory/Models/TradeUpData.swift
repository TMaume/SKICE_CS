import Foundation

// MARK: - Catalog Models

/// A single skin within a collection, usable as a trade-up contract output.
public struct TradeUpItem: Codable, Hashable, Identifiable, Sendable {
    public let weaponName: String
    public let skinName: String
    public let rarity: SkinRarity

    public var id: String { "\(weaponName)|\(skinName)" }
    public var displayName: String { "\(weaponName) | \(skinName)" }

    public init(weaponName: String, skinName: String, rarity: SkinRarity) {
        self.weaponName = weaponName
        self.skinName = skinName
        self.rarity = rarity
    }

    /// Builds the Steam market_hash_name used to look up a price for this
    /// item at a given exterior (and optional StatTrak™ prefix).
    public func marketHashName(exterior: SkinExterior, statTrak: Bool) -> String {
        let prefix = statTrak ? "StatTrak™ " : ""
        return "\(prefix)\(displayName) (\(exterior.rawValue))"
    }
}

/// A CS2 collection: its float (wear) bounds and the items it contains,
/// grouped by rarity. Used to resolve a trade-up's output pool.
public struct TradeUpCollection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let minFloat: Double
    public let maxFloat: Double
    public let items: [TradeUpItem]

    public init(id: String, name: String, minFloat: Double, maxFloat: Double, items: [TradeUpItem]) {
        self.id = id
        self.name = name
        self.minFloat = minFloat
        self.maxFloat = maxFloat
        self.items = items
    }

    public func items(ofRarity rarity: SkinRarity) -> [TradeUpItem] {
        items.filter { $0.rarity == rarity }
    }
}

// MARK: - Rarity trade-up helpers

public extension SkinRarity {
    /// The rarity one tier above this one for a Trade-Up Contract (10 × R → 1 × R+1).
    /// Returns nil for rarities that cannot be traded up (Covert, knives, contraband, default).
    var nextTradeUpRarity: SkinRarity? {
        switch self {
        case .consumer: return .industrial
        case .industrial: return .milSpec
        case .milSpec: return .restricted
        case .restricted: return .classified
        case .classified: return .covert
        case .defaultRarity, .covert, .extraordinary, .contraband: return nil
        }
    }

    /// True when items of this rarity can be used as trade-up contract inputs.
    var isTradeUpInputEligible: Bool { nextTradeUpRarity != nil }
}

// MARK: - Exterior ↔ float helpers

public extension SkinExterior {
    /// Maps a float value (0…1) to its standard CS2 exterior wear tier.
    static func forFloat(_ float: Double) -> SkinExterior {
        switch float {
        case ..<0.07: return .factoryNew
        case ..<0.15: return .minimalWear
        case ..<0.38: return .fieldTested
        case ..<0.45: return .wellWorn
        default: return .battleScarred
        }
    }

    /// A representative midpoint float for this exterior, used as an input float
    /// estimate when an item's exact float is not available.
    var representativeFloat: Double {
        switch self {
        case .factoryNew: return 0.035
        case .minimalWear: return 0.11
        case .fieldTested: return 0.265
        case .wellWorn: return 0.415
        case .battleScarred: return 0.725
        case .notPainted: return 0.5
        }
    }
}

// MARK: - Catalog

/// Static trade-up catalog. The collection/item data is embedded as JSON
/// (generated from ByMykel/CSGO-API skins.json) and decoded once, lazily, on
/// first use. The app performs no network access for this data.
public enum TradeUpCatalog {
    /// Every CS2 collection with its Consumer..Covert weapon skins.
    public static let collections: [TradeUpCollection] = {
        guard let data = TradeUpCatalogData.json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TradeUpCollection].self, from: data)) ?? []
    }()

    /// Finds a collection by display name or slug (case-insensitive).
    public static func collection(named name: String) -> TradeUpCollection? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return collections.first {
            $0.name.caseInsensitiveCompare(key) == .orderedSame
                || $0.id.caseInsensitiveCompare(key) == .orderedSame
        }
    }
}
