import Foundation

/// Top-level JSON response from `https://steamcommunity.com/inventory/<steamid64>/730/2`
public struct SteamInventoryResponse: Codable, Sendable {
    public let assets: [SteamAsset]?
    public let descriptions: [SteamDescription]?
    public let totalInventoryCount: Int?
    public let success: Int?
    public let rwgrsn: Int?
    public let moreItems: Int?
    public let lastAssetId: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case assets
        case descriptions
        case totalInventoryCount = "total_inventory_count"
        case success
        case rwgrsn
        case moreItems = "more_items"
        case lastAssetId = "last_assetid"
        case error
    }
}

/// Represents a unique item instance in a player's CS2 inventory.
public struct SteamAsset: Codable, Sendable, Hashable {
    public let appid: Int
    public let contextid: String
    public let assetid: String
    public let classid: String
    public let instanceid: String
    public let amount: String

    enum CodingKeys: String, CodingKey {
        case appid
        case contextid
        case assetid
        case classid
        case instanceid
        case amount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intAppId = try? container.decode(Int.self, forKey: .appid) {
            self.appid = intAppId
        } else if let strAppId = try? container.decode(String.self, forKey: .appid), let parsed = Int(strAppId) {
            self.appid = parsed
        } else {
            self.appid = 730
        }

        self.contextid = (try? container.decode(String.self, forKey: .contextid)) ?? "2"
        self.assetid = try container.decode(String.self, forKey: .assetid)
        self.classid = try container.decode(String.self, forKey: .classid)
        self.instanceid = (try? container.decode(String.self, forKey: .instanceid)) ?? "0"
        self.amount = (try? container.decode(String.self, forKey: .amount)) ?? "1"
    }
}

/// Shared metadata describing an item class and instance, including trade-lock and market restrictions.
public struct SteamDescription: Codable, Sendable, Hashable {
    public let appid: Int
    public let classid: String
    public let instanceid: String
    public let currency: Int?
    public let backgroundColor: String?
    public let iconUrl: String?
    public let iconUrlLarge: String?
    public let descriptions: [SteamDescriptionEntry]?
    public let ownerDescriptions: [SteamDescriptionEntry]?
    public let tradable: Int?
    public let marketable: Int?
    public let commodity: Int?
    public let marketTradableRestriction: Int?
    public let marketMarketableRestriction: Int?
    public let cacheExpiration: String?
    public let name: String
    public let nameColor: String?
    public let type: String?
    public let marketName: String?
    public let marketHashName: String?
    public let actions: [SteamItemAction]?
    public let marketActions: [SteamItemAction]?
    public let tags: [SteamItemTag]?

    enum CodingKeys: String, CodingKey {
        case appid
        case classid
        case instanceid
        case currency
        case backgroundColor = "background_color"
        case iconUrl = "icon_url"
        case iconUrlLarge = "icon_url_large"
        case descriptions
        case ownerDescriptions = "owner_descriptions"
        case tradable
        case marketable
        case commodity
        case marketTradableRestriction = "market_tradable_restriction"
        case marketMarketableRestriction = "market_marketable_restriction"
        case cacheExpiration = "cache_expiration"
        case name
        case nameColor = "name_color"
        case type
        case marketName = "market_name"
        case marketHashName = "market_hash_name"
        case actions
        case marketActions = "market_actions"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intAppId = try? container.decode(Int.self, forKey: .appid) {
            self.appid = intAppId
        } else if let strAppId = try? container.decode(String.self, forKey: .appid), let parsed = Int(strAppId) {
            self.appid = parsed
        } else {
            self.appid = 730
        }

        self.classid = try container.decode(String.self, forKey: .classid)
        self.instanceid = (try? container.decode(String.self, forKey: .instanceid)) ?? "0"
        self.currency = try? container.decode(Int.self, forKey: .currency)
        self.backgroundColor = try? container.decode(String.self, forKey: .backgroundColor)
        self.iconUrl = try? container.decode(String.self, forKey: .iconUrl)
        self.iconUrlLarge = try? container.decode(String.self, forKey: .iconUrlLarge)

        // Steam occasionally returns "" instead of [] when descriptions are empty
        self.descriptions = try? container.decode([SteamDescriptionEntry].self, forKey: .descriptions)
        self.ownerDescriptions = try? container.decode([SteamDescriptionEntry].self, forKey: .ownerDescriptions)

        self.tradable = try? container.decode(Int.self, forKey: .tradable)
        self.marketable = try? container.decode(Int.self, forKey: .marketable)
        self.commodity = try? container.decode(Int.self, forKey: .commodity)
        self.marketTradableRestriction = try? container.decode(Int.self, forKey: .marketTradableRestriction)
        self.marketMarketableRestriction = try? container.decode(Int.self, forKey: .marketMarketableRestriction)
        self.cacheExpiration = try? container.decode(String.self, forKey: .cacheExpiration)

        self.name = (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .marketName))
            ?? (try? container.decode(String.self, forKey: .marketHashName))
            ?? "Unknown CS2 Item"

        self.nameColor = try? container.decode(String.self, forKey: .nameColor)
        self.type = try? container.decode(String.self, forKey: .type)
        self.marketName = try? container.decode(String.self, forKey: .marketName)
        self.marketHashName = try? container.decode(String.self, forKey: .marketHashName)
        self.actions = try? container.decode([SteamItemAction].self, forKey: .actions)
        self.marketActions = try? container.decode([SteamItemAction].self, forKey: .marketActions)
        self.tags = try? container.decode([SteamItemTag].self, forKey: .tags)
    }
}

/// Detailed text or HTML line inside `descriptions` or `owner_descriptions`.
public struct SteamDescriptionEntry: Codable, Sendable, Hashable {
    public let type: String?
    public let value: String?
    public let color: String?
    public let name: String?
}

/// Action link such as "Inspect in Game..." containing the GC preview payload.
public struct SteamItemAction: Codable, Sendable, Hashable {
    public let link: String?
    public let name: String?
}

/// Localized categorization tag for weapon type, rarity, exterior, quality, or collection.
public struct SteamItemTag: Codable, Sendable, Hashable {
    public let category: String
    public let internalName: String
    public let localizedCategoryName: String?
    public let localizedTagName: String
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case category
        case internalName = "internal_name"
        case localizedCategoryName = "localized_category_name"
        case localizedTagName = "localized_tag_name"
        case color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.category = (try? container.decode(String.self, forKey: .category)) ?? "Other"
        self.internalName = (try? container.decode(String.self, forKey: .internalName)) ?? ""
        self.localizedCategoryName = try? container.decode(String.self, forKey: .localizedCategoryName)
        self.localizedTagName = (try? container.decode(String.self, forKey: .localizedTagName)) ?? self.internalName
        self.color = try? container.decode(String.self, forKey: .color)
    }
}