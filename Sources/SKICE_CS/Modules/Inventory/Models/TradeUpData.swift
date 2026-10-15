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

// MARK: - Local catalog (curated, illustrative subset — no third-party API)

private func catalogItem(_ weapon: String, _ skin: String, _ rarity: SkinRarity) -> TradeUpItem {
    TradeUpItem(weaponName: weapon, skinName: skin, rarity: rarity)
}

/// Static, Codable trade-up catalog. This is a curated representative subset of
/// popular CS2 collections for simulation purposes — not an exhaustive Valve dataset.
public enum TradeUpCatalog {
    public static let collections: [TradeUpCollection] = [
        TradeUpCollection(id: "phoenix", name: "The Phoenix Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("AWP", "Asiimov", .covert),
            catalogItem("AUG", "Chameleon", .classified),
            catalogItem("AK-47", "Redline", .restricted),
            catalogItem("P90", "Trigon", .restricted),
            catalogItem("AWP", "Electric Hive", .restricted),
            catalogItem("USP-S", "Guardian", .milSpec),
            catalogItem("Negev", "Terrain", .milSpec),
            catalogItem("P250", "Undertow", .milSpec)
        ]),

        TradeUpCollection(id: "chroma2", name: "The Chroma 2 Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("M4A1-S", "Hyper Beast", .covert),
            catalogItem("AWP", "Hyper Beast", .covert),
            catalogItem("AWP", "Man-o'-war", .classified),
            catalogItem("AK-47", "Elite Build", .restricted),
            catalogItem("P250", "Valence", .restricted),
            catalogItem("MAC-10", "Neon Rider", .milSpec),
            catalogItem("MP9", "Ruby Poison", .milSpec)
        ]),

        TradeUpCollection(id: "spectrum", name: "The Spectrum Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("AK-47", "Bloodsport", .covert),
            catalogItem("AWP", "Fever Dream", .covert),
            catalogItem("M4A1-S", "Golden Coil", .classified),
            catalogItem("CZ75-Auto", "Xiangliu", .classified),
            catalogItem("UMP-45", "Primal Saber", .restricted),
            catalogItem("SG 553", "Flashback", .restricted),
            catalogItem("PP-Bizon", "Judgement of Anubis", .milSpec)
        ]),

        TradeUpCollection(id: "dangerzone", name: "The Danger Zone Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("AK-47", "Asiimov", .covert),
            catalogItem("AWP", "Neo-Noir", .covert),
            catalogItem("Desert Eagle", "Mecha Industries", .restricted),
            catalogItem("M4A4", "Neo-Noir", .restricted),
            catalogItem("P250", "Asiimov", .milSpec),
            catalogItem("UMP-45", "Momentum", .milSpec)
        ]),

        TradeUpCollection(id: "fracture", name: "The Fracture Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("M4A1-S", "Printstream", .covert),
            catalogItem("AWP", "Exoskeleton", .covert),
            catalogItem("AK-47", "Legion of Anubis", .classified),
            catalogItem("Glock-18", "Vogue", .classified),
            catalogItem("P250", "Cyber Shell", .restricted),
            catalogItem("XM1014", "Incinegator", .restricted)
        ]),

        TradeUpCollection(id: "prisma2", name: "The Prisma 2 Collection", minFloat: 0.00, maxFloat: 0.80, items: [
            catalogItem("AWP", "Chromatic Aberration", .covert),
            catalogItem("M4A4", "The Emperor", .covert),
            catalogItem("AK-47", "Phantom Disruptor", .classified),
            catalogItem("MP7", "Bloodsport", .classified),
            catalogItem("Desert Eagle", "Printstream", .restricted),
            catalogItem("MP9", "Hypnotic", .restricted),
            catalogItem("P250", "Nevermore", .milSpec)
        ])
    ]

    /// Finds a collection by display name or slug (case-insensitive).
    public static func collection(named name: String) -> TradeUpCollection? {
        collections.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                || $0.id.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
