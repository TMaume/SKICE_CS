import Foundation

/// Standard CS2 item rarity tiers ordered from lowest to highest grade.
public enum SkinRarity: String, CaseIterable, Codable, Sendable, Comparable {
    case defaultRarity = "Default"
    case consumer = "Consumer Grade"
    case industrial = "Industrial Grade"
    case milSpec = "Mil-Spec Grade"
    case restricted = "Restricted"
    case classified = "Classified"
    case covert = "Covert"
    case extraordinary = "Extraordinary"
    case contraband = "Contraband"

    public var sortRank: Int {
        switch self {
        case .defaultRarity: return 0
        case .consumer: return 1
        case .industrial: return 2
        case .milSpec: return 3
        case .restricted: return 4
        case .classified: return 5
        case .covert: return 6
        case .extraordinary: return 7
        case .contraband: return 8
        }
    }

    public static func < (lhs: SkinRarity, rhs: SkinRarity) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    /// Maps Steam tag `internal_name` or `localized_tag_name` to a typed `SkinRarity`.
    public static func from(internalName: String?, localizedName: String?) -> SkinRarity {
        let internalLower = (internalName ?? "").lowercased()
        let localizedLower = (localizedName ?? "").lowercased()

        if internalLower.contains("contraband") || localizedLower.contains("contraband") {
            return .contraband
        } else if internalLower.contains("ancient_character") || localizedLower.contains("extraordinary") || localizedLower.contains("master") {
            return .extraordinary
        } else if internalLower.contains("ancient") || localizedLower.contains("covert") || localizedLower.contains("remarkable") {
            return .covert
        } else if internalLower.contains("legendary") || localizedLower.contains("classified") || localizedLower.contains("exotic") {
            return .classified
        } else if internalLower.contains("mythical") || localizedLower.contains("restricted") || localizedLower.contains("distinguished") {
            return .restricted
        } else if internalLower.contains("rare") || localizedLower.contains("mil-spec") || localizedLower.contains("high grade") {
            return .milSpec
        } else if internalLower.contains("uncommon") || localizedLower.contains("industrial") || localizedLower.contains("medium grade") {
            return .industrial
        } else if internalLower.contains("common") || localizedLower.contains("consumer") || localizedLower.contains("base grade") {
            return .consumer
        } else {
            return .defaultRarity
        }
    }
}

/// Standard CS2 skin wear / exterior conditions.
public enum SkinExterior: String, CaseIterable, Codable, Sendable {
    case factoryNew = "Factory New"
    case minimalWear = "Minimal Wear"
    case fieldTested = "Field-Tested"
    case wellWorn = "Well-Worn"
    case battleScarred = "Battle-Scarred"
    case notPainted = "Not Painted"

    /// Short badge label for compact UI cards.
    public var shortCode: String? {
        switch self {
        case .factoryNew: return "FN"
        case .minimalWear: return "MW"
        case .fieldTested: return "FT"
        case .wellWorn: return "WW"
        case .battleScarred: return "BS"
        case .notPainted: return nil
        }
    }

    public static func from(internalName: String?, localizedName: String?) -> SkinExterior {
        let internalLower = (internalName ?? "").lowercased()
        let localizedLower = (localizedName ?? "").lowercased()

        switch true {
        case internalLower == "wearcategory0" || localizedLower.contains("factory new"):
            return .factoryNew
        case internalLower == "wearcategory1" || localizedLower.contains("minimal wear"):
            return .minimalWear
        case internalLower == "wearcategory2" || localizedLower.contains("field-tested"):
            return .fieldTested
        case internalLower == "wearcategory3" || localizedLower.contains("well-worn"):
            return .wellWorn
        case internalLower == "wearcategory4" || localizedLower.contains("battle-scarred"):
            return .battleScarred
        default:
            return .notPainted
        }
    }
}

/// Represents the verified trade availability state of a CS2 inventory item.
public enum SkinTradeStatus: Hashable, Sendable {
    /// Item has `tradable == 1` and can be traded immediately.
    case tradable
    /// Item has `tradable == 0` AND carries a verified future expiration date or explicit "Tradable After" timestamp.
    case tradeCooldown(expirationDate: Date?, untilDateText: String)
    /// Item has `tradable == 0` and no expiration timestamp (e.g., Service Medals, Storage Units, base items).
    case untradable

    /// Compact badge label for grid and list cards. Never fabricates a "7D LOCK" from static class rules.
    public var badgeLabel: String? {
        switch self {
        case .tradable:
            return nil
        case .tradeCooldown(let expirationDate, _):
            if let expirationDate {
                let remainingSeconds = expirationDate.timeIntervalSinceNow
                if remainingSeconds > 0 {
                    let totalHours = Int(ceil(remainingSeconds / 3600.0))
                    if totalHours >= 24 {
                        let days = Int(ceil(Double(totalHours) / 24.0))
                        return "\(days)D LEFT"
                    } else {
                        return "\(max(1, totalHours))H LEFT"
                    }
                }
            }
            return "COOLDOWN"
        case .untradable:
            return "UNTRADABLE"
        }
    }

    /// Detailed human-readable description for the item inspection sheet.
    public var detailedDescription: String {
        switch self {
        case .tradable:
            return "Tradable Immediately"
        case .tradeCooldown(_, let untilDateText):
            return untilDateText
        case .untradable:
            return "Not Tradable"
        }
    }
}

/// Clean, UI-ready domain model representing a single item in a user's CS2 inventory.
public struct SkinItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let assetId: String
    public let classId: String
    public let instanceId: String
    public let amount: Int

    public let fullName: String
    public let weaponName: String?
    public let skinPatternName: String
    public let marketHashName: String
    public let categoryType: String
    public let collectionName: String?

    public let rarity: SkinRarity
    public let rarityLocalizedName: String
    public let rarityColorHex: String?
    public let exterior: SkinExterior

    public let isStatTrak: Bool
    public let isSouvenir: Bool
    public let isMeleeOrGloves: Bool
    public let isTradable: Bool
    public let isMarketable: Bool
    /// Static class-level restriction duration defined by Valve (not an active timer by itself).
    public let tradeRestrictionDays: Int?
    public let tradeStatus: SkinTradeStatus

    public let iconURL: URL?
    public let inspectLink: String?

    /// True only if the item has an active, verified trade cooldown timestamp.
    public var isOnTradeCooldown: Bool {
        if case .tradeCooldown = tradeStatus { return true }
        return false
    }

    /// True if the item is non-tradable and has no cooldown expiration timer.
    public var isPermanentlyUntradable: Bool {
        if case .untradable = tradeStatus { return true }
        return false
    }

    public var isTradeRestricted: Bool {
        !isTradable
    }

    private static let steamImageBaseURL = "https://community.akamai.steamstatic.com/economy/image/"

    public init(
        asset: SteamAsset,
        description: SteamDescription,
        ownerSteamID64: String
    ) {
        self.id = asset.assetid
        self.assetId = asset.assetid
        self.classId = asset.classid
        self.instanceId = asset.instanceid
        self.amount = Int(asset.amount) ?? 1

        self.fullName = description.name
        self.marketHashName = description.marketHashName ?? description.marketName ?? description.name

        // Evaluate actual trade status first; if a cache_expiration date has already passed, treat as tradable
        let resolvedStatus = Self.resolveTradeStatus(from: description)
        self.tradeStatus = resolvedStatus
        if case .tradable = resolvedStatus {
            self.isTradable = true
        } else {
            self.isTradable = false
        }

        self.isMarketable = (description.marketable ?? 0) == 1
        self.tradeRestrictionDays = description.marketTradableRestriction

        // Extract tags by category
        let tags = description.tags ?? []
        let typeTag = tags.first { $0.category.caseInsensitiveCompare("Type") == .orderedSame }
        let weaponTag = tags.first { $0.category.caseInsensitiveCompare("Weapon") == .orderedSame }
        let rarityTag = tags.first { $0.category.caseInsensitiveCompare("Rarity") == .orderedSame }
        let exteriorTag = tags.first { $0.category.caseInsensitiveCompare("Exterior") == .orderedSame }
        let qualityTag = tags.first { $0.category.caseInsensitiveCompare("Quality") == .orderedSame }
        let itemSetTag = tags.first { $0.category.caseInsensitiveCompare("ItemSet") == .orderedSame }

        self.categoryType = Self.cleanTypeLabel(typeTag?.localizedTagName ?? description.type ?? "Other")
        self.collectionName = itemSetTag?.localizedTagName

        // Rarity & Exterior
        self.rarity = SkinRarity.from(
            internalName: rarityTag?.internalName,
            localizedName: rarityTag?.localizedTagName ?? description.type
        )
        self.rarityLocalizedName = rarityTag?.localizedTagName ?? self.rarity.rawValue
        self.rarityColorHex = rarityTag?.color ?? description.nameColor

        let resolvedExterior = SkinExterior.from(
            internalName: exteriorTag?.internalName,
            localizedName: exteriorTag?.localizedTagName ?? description.name
        )
        self.exterior = resolvedExterior

        // Quality flags (StatTrak, Souvenir, ★ Star for Knives/Gloves)
        let qualityInternal = (qualityTag?.internalName ?? "").lowercased()
        self.isStatTrak = qualityInternal.contains("strange") || description.name.contains("StatTrak™")
        self.isSouvenir = qualityInternal.contains("tournament") || description.name.contains("Souvenir")
        self.isMeleeOrGloves = qualityInternal.contains("unusual") || description.name.contains("★")

        // Parse clean weapon & pattern names from "★ StatTrak™ Karambit | Doppler (Factory New)"
        let cleanedName = Self.stripExteriorSuffix(
            from: description.name
                .replacingOccurrences(of: "★ ", with: "")
                .replacingOccurrences(of: "StatTrak™ ", with: "")
                .replacingOccurrences(of: "Souvenir ", with: "")
        )

        let parts = cleanedName.components(separatedBy: " | ")
        if parts.count >= 2 {
            self.weaponName = weaponTag?.localizedTagName ?? parts[0].trimmingCharacters(in: .whitespaces)
            self.skinPatternName = parts.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
        } else {
            self.weaponName = weaponTag?.localizedTagName
            self.skinPatternName = cleanedName
        }

        // Icon URL construction
        let rawIconPath = (description.iconUrlLarge?.isEmpty == false)
            ? description.iconUrlLarge
            : description.iconUrl

        if let rawIconPath, !rawIconPath.isEmpty {
            self.iconURL = URL(string: "\(Self.steamImageBaseURL)\(rawIconPath)/360fx360f")
        } else {
            self.iconURL = nil
        }

        // Resolve Game Coordinator Inspect Link placeholders for Phase 2 Float/Seed extraction
        let rawInspect = description.actions?.first?.link ?? description.marketActions?.first?.link
        if let rawInspect, !rawInspect.isEmpty {
            self.inspectLink = rawInspect
                .replacingOccurrences(of: "%owner_steamid%", with: ownerSteamID64)
                .replacingOccurrences(of: "%assetid%", with: asset.assetid)
        } else {
            self.inspectLink = nil
        }
    }

    /// Fallback initializer when Steam returns an asset whose description entry is missing.
    public init(unmatchedAsset: SteamAsset) {
        self.id = unmatchedAsset.assetid
        self.assetId = unmatchedAsset.assetid
        self.classId = unmatchedAsset.classid
        self.instanceId = unmatchedAsset.instanceid
        self.amount = Int(unmatchedAsset.amount) ?? 1

        self.fullName = "CS2 Item #\(unmatchedAsset.assetid)"
        self.weaponName = "Classified Asset"
        self.skinPatternName = "Asset #\(unmatchedAsset.assetid)"
        self.marketHashName = "CS2 Item #\(unmatchedAsset.assetid)"
        self.categoryType = "Other"
        self.collectionName = nil

        self.rarity = .defaultRarity
        self.rarityLocalizedName = "Default"
        self.rarityColorHex = nil
        self.exterior = .notPainted

        self.isStatTrak = false
        self.isSouvenir = false
        self.isMeleeOrGloves = false
        self.isTradable = false
        self.isMarketable = false
        self.tradeRestrictionDays = nil
        self.tradeStatus = .untradable

        self.iconURL = nil
        self.inspectLink = nil
    }

    // MARK: - Private Trade Status Resolution

    /// Determines whether an item is tradable, on a verified timed cooldown, or permanently untradable.
    /// Does NOT use `market_tradable_restriction` as a fallback because Steam sets `market_tradable_restriction = 7`
    /// on nearly all CS2 item definitions (including Service Medals, Coins, and Storage Units).
    private static func resolveTradeStatus(from description: SteamDescription, now: Date = Date()) -> SkinTradeStatus {
        if (description.tradable ?? 0) == 1 {
            return .tradable
        }

        // 1. Check if `cache_expiration` exists and points to a valid future date
        let parsedExpirationDate = parseISO8601Date(description.cacheExpiration)

        // 2. Inspect `owner_descriptions` and `descriptions` for explicit "Tradable After..." text
        let allEntries = (description.ownerDescriptions ?? []) + (description.descriptions ?? [])
        for entry in allEntries {
            guard let rawValue = entry.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty else {
                continue
            }
            let cleanedText = stripHTMLTags(from: rawValue)
            let lower = cleanedText.lowercased()

            if lower.contains("tradable after")
                || lower.contains("tradable/marketable after")
                || lower.contains("marketable after") {
                if let expDate = parsedExpirationDate, expDate <= now {
                    return .tradable
                }
                return .tradeCooldown(expirationDate: parsedExpirationDate, untilDateText: cleanedText)
            }
        }

        // 3. If `cache_expiration` is a valid future timestamp without a description line, use it directly
        if let expDate = parsedExpirationDate {
            if expDate > now {
                let formattedDate = formatCooldownDate(expDate)
                return .tradeCooldown(
                    expirationDate: expDate,
                    untilDateText: "Tradable After \(formattedDate)"
                )
            } else {
                // Cooldown has already expired in Steam's cache
                return .tradable
            }
        }

        // 4. No future expiration date or cooldown text exists -> item is Not Tradable
        return .untradable
    }

    private static func parseISO8601Date(_ isoString: String?) -> Date? {
        guard let isoString = isoString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !isoString.isEmpty else {
            return nil
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        if let date = standardFormatter.date(from: isoString) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: isoString)
    }

    private static func formatCooldownDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm 'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func stripHTMLTags(from text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripExteriorSuffix(from name: String) -> String {
        var result = name
        for exterior in SkinExterior.allCases where exterior != .notPainted {
            let suffix = " (\(exterior.rawValue))"
            if result.hasSuffix(suffix) {
                result.removeLast(suffix.count)
                break
            }
        }
        return result
    }

    private static func cleanTypeLabel(_ rawType: String) -> String {
        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Other" : trimmed
    }
}
