import Foundation

/// Decodes the Game Coordinator ClientWelcome payload into item inspections.
///
/// The GC reply carries CSOEconItem objects (the type-1 inventory SO-cache)
/// whose economy attributes the public Steam Web API cannot provide: exact
/// float, pattern seed, StatTrak kill count, and applied stickers.
enum GameCoordinatorDecoder {

    // MARK: - Protobuf decoding (CSOEconItem path)

    /// The subset of CSOEconItem attributes the inventory needs: exact float,
    /// pattern seed, the StatTrak kill counter, and applied stickers.
    private struct EconAttributes {
        var paintIndex: UInt32 = 0
        var paintWear: Float?
        var paintSeed: UInt32?
        var killEaterValue: UInt32?
        var killEaterScoreType: UInt32?
        var stickerIDs: [Int: UInt32] = [:]
        var stickerWears: [Int: Float] = [:]
    }

    /// Decodes the ClientWelcome's subscribed SO caches into a flat list of
    /// item inspections (one per CSOEconItem in the inventory cache, type 1).
    static func decodeWelcome(_ data: Data) -> [GCItemInspection] {
        var inspections: [GCItemInspection] = []
        var decoder = ProtobufDecoder(data)
        var cacheCount = 0
        while let (field, wire) = decoder.readTag() {
            if field == 3, wire == 2, let cacheBytes = decoder.readLengthDelimited() {
                cacheCount += 1
                // CMsgClientWelcome.outofdate_subscribed_caches -> CMsgSOCacheSubscribed
                decodeCache(cacheBytes, into: &inspections)
            } else {
                decoder.skip(wireType: wire)
            }
        }
        gcInfo(
            "GC decodeWelcome: \(cacheCount) caches, \(inspections.count) item inspections"
        )
        return inspections
    }

    private static func decodeCache(_ data: Data, into inspections: inout [GCItemInspection]) {
        var decoder = ProtobufDecoder(data)
        while let (field, wire) = decoder.readTag() {
            if field == 2, wire == 2, let objectBytes = decoder.readLengthDelimited() {
                // CMsgSOCacheSubscribed.objects -> SubscribedType
                decodeSubscribedType(objectBytes, into: &inspections)
            } else {
                decoder.skip(wireType: wire)
            }
        }
    }

    private static func decodeSubscribedType(_ data: Data, into inspections: inout [GCItemInspection]) {
        var typeID: Int32 = 0
        var objects: [Data] = []
        var decoder = ProtobufDecoder(data)
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 1:
                if let value = decoder.readVarint() {
                    typeID = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
                }
            case 2:
                if wire == 2, let value = decoder.readLengthDelimited() { objects.append(value) }
            default:
                decoder.skip(wireType: wire)
            }
        }
        switch typeID {
        case 1:
            // type_id 1 = the player's inventory of CSOEconItem objects. Each
            // carries the economy attributes the public Web API omits (float,
            // seed, kill counter, stickers).
            for object in objects {
                if let inspection = decodeEconItem(object) {
                    inspections.append(inspection)
                }
            }
            gcInfo("GC inventory cache: \(objects.count) items")
        default:
            gcInfo("GC subscribed type \(typeID) skipped (\(objects.count) objects)")
        }
    }

    /// Decodes a CSOEconItem into a GCItemInspection (id + def_index + float /
    /// seed / kill counter / stickers). Returns nil for entries without an id.
    private static func decodeEconItem(_ data: Data) -> GCItemInspection? {
        var id: UInt64 = 0
        var defIndex: UInt32 = 0
        var attrs = EconAttributes()

        var decoder = ProtobufDecoder(data)
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 1: // id
                if let value = decoder.readVarint() { id = value }
            case 4: // def_index
                if let value = decoder.readVarint() { defIndex = UInt32(truncatingIfNeeded: value) }
            case 12: // attribute (repeated CSOEconItemAttribute)
                if wire == 2, var attrDecoder = decoder.readMessage() {
                    decodeAttribute(&attrDecoder, into: &attrs)
                } else {
                    decoder.skip(wireType: wire)
                }
            default:
                decoder.skip(wireType: wire)
            }
        }
        guard id != 0 else { return nil }

        let stickers = attrs.stickerIDs.keys.sorted().compactMap { slot -> GCSticker? in
            guard let stickerID = attrs.stickerIDs[slot], stickerID != 0 else { return nil }
            return GCSticker(slot: slot, stickerID: stickerID, wear: attrs.stickerWears[slot])
        }

        return GCItemInspection(
            itemID: id,
            defIndex: defIndex,
            paintIndex: attrs.paintIndex,
            paintWear: attrs.paintWear,
            paintSeed: attrs.paintSeed,
            killEaterValue: attrs.killEaterValue,
            killEaterScoreType: attrs.killEaterScoreType,
            stickers: stickers,
            updatedAt: Date()
        )
    }

    /// Decodes one CSOEconItemAttribute into the accumulator. Def indices come
    /// from items_game.txt: 6 = paint index, 7 = seed, 8 = wear, 80 = kill eater,
    /// 81 = kill eater score type, 113 + 4*slot = sticker slot id.
    private static func decodeAttribute(_ decoder: inout ProtobufDecoder, into attrs: inout EconAttributes) {
        var defIndex: UInt32 = 0
        var value: UInt32 = 0
        var valueBytes = Data()
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 1: // def_index
                if let v = decoder.readVarint() { defIndex = UInt32(truncatingIfNeeded: v) }
            case 2: // value (uint32)
                if let v = decoder.readVarint() { value = UInt32(truncatingIfNeeded: v) }
            case 3: // value_bytes
                if wire == 2, let b = decoder.readLengthDelimited() { valueBytes = b }
            default:
                decoder.skip(wireType: wire)
            }
        }
        switch defIndex {
        case 6: // paint index
            let paint = uintAttribute(value: value, valueBytes: valueBytes)
            if paint > 0 { attrs.paintIndex = paint }
        case 7: // pattern seed
            attrs.paintSeed = uintAttribute(value: value, valueBytes: valueBytes)
        case 8: // wear float
            attrs.paintWear = floatAttribute(value: value, valueBytes: valueBytes)
        case 80: // kill eater (StatTrak count)
            attrs.killEaterValue = value
        case 81: // kill eater score type
            attrs.killEaterScoreType = value
        case 113...132: // sticker slots 0-4: id, wear, scale, rotation
            let offset = Int(defIndex) - 113
            let slot = offset / 4
            switch offset % 4 {
            case 0: attrs.stickerIDs[slot] = value
            case 1: attrs.stickerWears[slot] = floatAttribute(value: value, valueBytes: valueBytes) ?? 0
            default: break
            }
        default:
            break
        }
    }

    /// Reads a little-endian IEEE 754 float from the first 4 bytes.
    private static func floatLE(from data: Data) -> Float? {
        guard data.count >= 4 else { return nil }
        let s = data.startIndex
        let bits = UInt32(data[s]) | (UInt32(data[s + 1]) << 8) | (UInt32(data[s + 2]) << 16) | (UInt32(data[s + 3]) << 24)
        return Float(bitPattern: bits)
    }

    /// Attribute value as a UInt32: prefers the 4-byte float in value_bytes,
    /// falls back to the integer value.
    private static func uintAttribute(value: UInt32, valueBytes: Data) -> UInt32 {
        if valueBytes.count >= 4, let f = floatLE(from: valueBytes) {
            return UInt32(f.rounded())
        }
        return value
    }

    /// Attribute value as a Float: prefers value_bytes, falls back to the raw
    /// bits of value when the attribute is stored as a uint32.
    private static func floatAttribute(value: UInt32, valueBytes: Data) -> Float? {
        if valueBytes.count >= 4, let f = floatLE(from: valueBytes) {
            return f
        }
        if value != 0 {
            return Float(bitPattern: value)
        }
        return nil
    }

    // MARK: - Ranking decode (MatchmakingGC2ClientHello)

    /// Decodes CMsgGCCStrike15_v2_MatchmakingGC2ClientHello into ranked-ladder
    /// entries. Field 7 holds a single ranking and field 20 a repeated list;
    /// both are PlayerRankingInfo messages.
    static func decodeMatchmakingHello(_ data: Data) -> [PlayerRankingInfo] {
        var rankings: [PlayerRankingInfo] = []
        var decoder = ProtobufDecoder(data)
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 7, 20:
                if wire == 2, let bytes = decoder.readLengthDelimited() {
                    if let info = decodePlayerRankingInfo(bytes) {
                        rankings.append(info)
                    }
                } else {
                    decoder.skip(wireType: wire)
                }
            default:
                decoder.skip(wireType: wire)
            }
        }
        return rankings
    }

    /// Decodes a single PlayerRankingInfo message. Field numbers are
    /// authoritative (cstrike15_gcmessages.proto); the meaning of rank_type_id
    /// and rank_id is provisional until confirmed on-device.
    private static func decodePlayerRankingInfo(_ data: Data) -> PlayerRankingInfo? {
        var accountID: UInt32 = 0
        var rankID: UInt32 = 0
        var wins: UInt32 = 0
        var rankChange: Float = 0
        var rankTypeID: UInt32 = 0
        var rankWindowStats: UInt64 = 0
        var leaderboardName: String?
        var rankIfWin: UInt32 = 0
        var rankIfLose: UInt32 = 0
        var rankIfTie: UInt32 = 0
        var highestRank: UInt32 = 0
        var rankExpiry: UInt32 = 0

        var decoder = ProtobufDecoder(data)
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 1: // account_id
                if let v = decoder.readVarint() { accountID = UInt32(truncatingIfNeeded: v) }
            case 2: // rank_id
                if let v = decoder.readVarint() { rankID = UInt32(truncatingIfNeeded: v) }
            case 3: // wins
                if let v = decoder.readVarint() { wins = UInt32(truncatingIfNeeded: v) }
            case 4: // rank_change (float, fixed32)
                if wire == 5, let v = decoder.readFixed32() {
                    rankChange = Float(bitPattern: v)
                } else {
                    decoder.skip(wireType: wire)
                }
            case 6: // rank_type_id
                if let v = decoder.readVarint() { rankTypeID = UInt32(truncatingIfNeeded: v) }
            case 8: // rank_window_stats (uint64)
                if let v = decoder.readVarint() { rankWindowStats = v }
            case 9: // leaderboard_name (string)
                if wire == 2, let s = decoder.readString() {
                    leaderboardName = s
                } else {
                    decoder.skip(wireType: wire)
                }
            case 10: // rank_if_win
                if let v = decoder.readVarint() { rankIfWin = UInt32(truncatingIfNeeded: v) }
            case 11: // rank_if_lose
                if let v = decoder.readVarint() { rankIfLose = UInt32(truncatingIfNeeded: v) }
            case 12: // rank_if_tie
                if let v = decoder.readVarint() { rankIfTie = UInt32(truncatingIfNeeded: v) }
            case 15: // highest_rank
                if let v = decoder.readVarint() { highestRank = UInt32(truncatingIfNeeded: v) }
            case 16: // rank_expiry
                if let v = decoder.readVarint() { rankExpiry = UInt32(truncatingIfNeeded: v) }
            default:
                decoder.skip(wireType: wire)
            }
        }

        guard accountID != 0 else { return nil }

        return PlayerRankingInfo(
            accountID: accountID,
            rankID: rankID,
            wins: wins,
            rankChange: rankChange,
            rankTypeID: rankTypeID,
            rankWindowStats: rankWindowStats,
            leaderboardName: leaderboardName,
            rankIfWin: rankIfWin,
            rankIfLose: rankIfLose,
            rankIfTie: rankIfTie,
            highestRank: highestRank,
            rankExpiry: rankExpiry
        )
    }
}
