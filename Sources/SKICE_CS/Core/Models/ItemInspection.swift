import Foundation

/// A sticker applied to an item, as reported by the Game Coordinator.
public struct GCSticker: Codable, Sendable, Equatable {
    /// Sticker slot index (0 is the leftmost slot).
    public let slot: Int
    /// Sticker definition id.
    public let stickerID: UInt32
    /// Scrape/wear 0 (pristine) .. 1 (fully scraped), when reported.
    public let wear: Float?

    public init(slot: Int, stickerID: UInt32, wear: Float?) {
        self.slot = slot
        self.stickerID = stickerID
        self.wear = wear
    }
}

/// Game Coordinator item inspection data: the economy attributes the public
/// Steam Web API does NOT expose — exact float, pattern seed, the StatTrak kill
/// counter, and applied stickers.
///
/// Read from the GC item cache and stored on-device through ItemInspectionStore.
/// Zero-trust: recorded locally, never transmitted.
public struct GCItemInspection: Codable, Sendable, Equatable {
    /// The item / asset id (matches the Steam inventory asset id).
    public let itemID: UInt64
    /// Weapon / item definition index.
    public let defIndex: UInt32
    /// Paint kit index (0 = no finish).
    public let paintIndex: UInt32
    /// Exact wear float, 0 (Factory New) .. 1 (Battle-Scarred).
    public let paintWear: Float?
    /// Pattern seed / template index.
    public let paintSeed: UInt32?
    /// StatTrak kill count ("kill eater"), when present.
    public let killEaterValue: UInt32?
    /// StatTrak presence type ("kill eater score type").
    public let killEaterScoreType: UInt32?
    /// Applied stickers, ordered by slot.
    public let stickers: [GCSticker]
    /// When this inspection was last refreshed from the Game Coordinator.
    public let updatedAt: Date

    public init(
        itemID: UInt64,
        defIndex: UInt32,
        paintIndex: UInt32,
        paintWear: Float?,
        paintSeed: UInt32?,
        killEaterValue: UInt32?,
        killEaterScoreType: UInt32?,
        stickers: [GCSticker],
        updatedAt: Date
    ) {
        self.itemID = itemID
        self.defIndex = defIndex
        self.paintIndex = paintIndex
        self.paintWear = paintWear
        self.paintSeed = paintSeed
        self.killEaterValue = killEaterValue
        self.killEaterScoreType = killEaterScoreType
        self.stickers = stickers
        self.updatedAt = updatedAt
    }

    /// Asset id as the string the inventory uses.
    public var assetID: String { String(itemID) }

    /// True when the item carries a StatTrak kill counter.
    public var isStatTrak: Bool {
        killEaterValue != nil || (killEaterScoreType ?? 0) != 0
    }

    /// True when the item carries any applied sticker.
    public var hasStickers: Bool { !stickers.isEmpty }

    /// Exact float formatted to 8 decimals (Valve's convention), or nil.
    public var wearText: String? {
        guard let paintWear else { return nil }
        return String(format: "%.8f", paintWear)
    }
}
