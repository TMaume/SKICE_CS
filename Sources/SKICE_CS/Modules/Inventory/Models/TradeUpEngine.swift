import Foundation

// MARK: - Double helper

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// A single input to a Trade-Up Contract, reduced to the fields the engine needs.
public struct TradeUpInput: Sendable, Hashable {
    public let assetId: String
    public let collectionName: String
    public let rarity: SkinRarity
    public let float: Double
    public let isStatTrak: Bool
    public let isSouvenir: Bool

    public init(
        assetId: String,
        collectionName: String,
        rarity: SkinRarity,
        float: Double,
        isStatTrak: Bool,
        isSouvenir: Bool
    ) {
        self.assetId = assetId
        self.collectionName = collectionName
        self.rarity = rarity
        self.float = float
        self.isStatTrak = isStatTrak
        self.isSouvenir = isSouvenir
    }

    /// Builds an input from an inventory item, estimating its float from its
    /// exterior wear tier (exact float is not present in the inventory payload).
    public init(item: SkinItem) {
        self.assetId = item.id
        self.collectionName = item.collectionName ?? ""
        self.rarity = item.rarity
        self.float = item.exterior.representativeFloat
        self.isStatTrak = item.isStatTrak
        self.isSouvenir = item.isSouvenir
    }
}

/// A possible result of a Trade-Up Contract, with its probability and output float.
public struct TradeUpOutcome: Identifiable, Sendable, Hashable {
    public let collection: TradeUpCollection
    public let item: TradeUpItem
    public let probability: Double
    public let outputFloat: Double
    public let isStatTrak: Bool

    public var id: String { "\(item.id)|\(isStatTrak)" }

    /// Steam market hash name for this outcome at the computed exterior.
    public var marketHashName: String {
        item.marketHashName(exterior: SkinExterior.forFloat(outputFloat), statTrak: isStatTrak)
    }

    /// Probability expressed as a percentage string (e.g. "25.0%").
    public var probabilityPercent: String {
        String(format: "%.1f%%", probability * 100)
    }
}

/// Result of evaluating a contract: the resolved outcomes plus bookkeeping for
/// majority collections the local catalog could not resolve.
public struct TradeUpEvaluation: Sendable {
    public let outputRarity: SkinRarity
    public let isStatTrakOutput: Bool
    public let majorityCollections: [String]
    public let resolvedCollections: [String]
    public let unresolvedCollections: [String]
    public let outcomes: [TradeUpOutcome]

    public var hasOutcomes: Bool { !outcomes.isEmpty }
    public var isFullyResolved: Bool { unresolvedCollections.isEmpty }

    public init(
        outputRarity: SkinRarity,
        isStatTrakOutput: Bool,
        majorityCollections: [String],
        resolvedCollections: [String],
        unresolvedCollections: [String],
        outcomes: [TradeUpOutcome]
    ) {
        self.outputRarity = outputRarity
        self.isStatTrakOutput = isStatTrakOutput
        self.majorityCollections = majorityCollections
        self.resolvedCollections = resolvedCollections
        self.unresolvedCollections = unresolvedCollections
        self.outcomes = outcomes
    }
}

/// Pure, deterministic engine for the CS2 Trade-Up Contract rules.
/// No network access — collection data and probabilities are computed locally.
public enum TradeUpEngine {

    /// A Trade-Up Contract always consumes exactly 10 items of the same rarity.
    public static let contractSize = 10

    public enum TradeUpError: Error, LocalizedError, Equatable {
        case wrongCount(Int)
        case mixedRarity
        case mixedStatTrak
        case souvenirPresent
        case notTradeUpAble(SkinRarity)
        case missingCollection

        public var errorDescription: String? {
            switch self {
            case .wrongCount(let count):
                return "A Trade-Up Contract needs exactly 10 items (currently \(count))."
            case .mixedRarity:
                return "All 10 items must share the same rarity."
            case .mixedStatTrak:
                return "You cannot mix StatTrak™ and non-StatTrak™ items in a contract."
            case .souvenirPresent:
                return "Souvenir items cannot be used in a Trade-Up Contract."
            case .notTradeUpAble(let rarity):
                return "\(rarity.rawValue) items cannot be traded up."
            case .missingCollection:
                return "Some items have no collection tag and cannot be traded up."
            }
        }
    }

    /// Evaluates a trade-up and returns every possible outcome with its probability,
    /// sorted most-likely first. Throws TradeUpError only on hard rule violations.
    ///
    /// Valve rules implemented:
    /// - 10 items of the same rarity R → 1 item of rarity R+1.
    /// - Output collection = the majority collection among the 10 inputs
    ///   (uniform random tie-break when several collections tie for the most).
    /// - Output item = uniform random among the R+1 items of the chosen collection.
    /// - Output float = average of input floats, normalized by each collection's
    ///   min/max float bounds, then mapped back onto the output collection's bounds.
    /// - StatTrak: all-StatTrak → StatTrak output; all non-StatTrak → non-StatTrak.
    /// - Souvenir items are rejected.
    ///
    /// Majority collections that are missing from the local catalog are reported
    /// in unresolvedCollections rather than treated as an error.
    public static func evaluate(_ inputs: [TradeUpInput]) throws -> TradeUpEvaluation {
        guard inputs.count == contractSize else {
            throw TradeUpError.wrongCount(inputs.count)
        }

        let rarities = Set(inputs.map(\.rarity))
        guard rarities.count == 1, let inputRarity = rarities.first else {
            throw TradeUpError.mixedRarity
        }
        guard let outputRarity = inputRarity.nextTradeUpRarity else {
            throw TradeUpError.notTradeUpAble(inputRarity)
        }

        guard !inputs.contains(where: \.isSouvenir) else {
            throw TradeUpError.souvenirPresent
        }

        guard !inputs.contains(where: { $0.collectionName.isEmpty }) else {
            throw TradeUpError.missingCollection
        }

        let statTrakCount = inputs.filter(\.isStatTrak).count
        guard statTrakCount == 0 || statTrakCount == contractSize else {
            throw TradeUpError.mixedStatTrak
        }
        let isStatTrakOutput = statTrakCount == contractSize

        // Count how many inputs belong to each collection.
        var counts: [String: Int] = [:]
        for input in inputs {
            counts[input.collectionName, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        let majorityNames = counts.filter { $0.value == maxCount }.map(\.key).sorted()
        let tieCount = majorityNames.count

        // Normalize each input float within its collection's [min, max] bounds,
        // then average. This is the "weighted by collection min/max" averaging.
        let normalizedValues = inputs.map { input -> Double in
            guard let collection = TradeUpCatalog.collection(named: input.collectionName) else {
                return input.float.clamped(to: 0...1)
            }
            let span = max(collection.maxFloat - collection.minFloat, 0.0001)
            return ((input.float - collection.minFloat) / span).clamped(to: 0...1)
        }
        let avgNormalized = normalizedValues.reduce(0, +) / Double(normalizedValues.count)

        var outcomes: [TradeUpOutcome] = []
        var resolved: [String] = []
        var unresolved: [String] = []

        for name in majorityNames {
            guard let collection = TradeUpCatalog.collection(named: name) else {
                unresolved.append(name)
                continue
            }
            let outputItems = collection.items(ofRarity: outputRarity)
            guard !outputItems.isEmpty else {
                unresolved.append(name)
                continue
            }
            resolved.append(name)

            // Each tied-majority collection is equally likely; each of its
            // R+1 items is equally likely within that collection.
            let itemProbability = (1.0 / Double(tieCount)) / Double(outputItems.count)

            let outputSpan = max(collection.maxFloat - collection.minFloat, 0.0001)
            let outputFloat = (collection.minFloat + avgNormalized * outputSpan).clamped(to: 0...1)

            for item in outputItems {
                outcomes.append(
                    TradeUpOutcome(
                        collection: collection,
                        item: item,
                        probability: itemProbability,
                        outputFloat: outputFloat,
                        isStatTrak: isStatTrakOutput
                    )
                )
            }
        }

        let sorted = outcomes.sorted { lhs, rhs in
            if lhs.probability != rhs.probability { return lhs.probability > rhs.probability }
            return lhs.item.displayName < rhs.item.displayName
        }

        return TradeUpEvaluation(
            outputRarity: outputRarity,
            isStatTrakOutput: isStatTrakOutput,
            majorityCollections: majorityNames,
            resolvedCollections: resolved,
            unresolvedCollections: unresolved,
            outcomes: sorted
        )
    }

    /// True when an inventory item can serve as a trade-up input: a weapon skin
    /// of a trade-up-able rarity, carrying a collection tag, and not a souvenir,
    /// knife or glove. The collection does not have to be in the local catalog —
    /// such contracts are reported as unresolved rather than hidden.
    public static func isEligible(_ item: SkinItem) -> Bool {
        guard item.rarity.isTradeUpInputEligible else { return false }
        guard !item.isSouvenir, !item.isMeleeOrGloves else { return false }
        guard let collection = item.collectionName, !collection.isEmpty else { return false }

        let category = item.categoryType.lowercased()
        let excluded = [
            "agent", "sticker", "container", "music", "graffiti",
            "collectible", "patch", "key", "tag", "tool", "gift",
            "case", "capsule", "spray", "pass", "coin", "medal"
        ]
        return !excluded.contains { category.contains($0) }
    }
}
