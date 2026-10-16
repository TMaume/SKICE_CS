import Foundation

/// Minimal protobuf wire-format reader, hand-rolled to keep the package free of
/// any SPM dependency (ROADMAP ADR-06). Complements `ProtobufEncoder`.
///
/// It is a cursor over a byte buffer. Call `readTag()` to walk fields, then
/// read each field with the matching scalar/bytes accessor, or `skip(wireType:)`
/// to ignore an unknown field. Nested messages are decoded by taking the
/// length-delimited payload and constructing a new decoder over it.
public struct ProtobufDecoder: Sendable {
    public let data: Data
    private var index: Int

    public init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    public var isAtEnd: Bool { index >= data.endIndex }

    // MARK: - Primitives

    public mutating func readVarint() -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex {
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift >= 64 { return nil } // malformed (overlong) varint
        }
        return nil
    }

    public mutating func readFixed32() -> UInt32? {
        guard index + 4 <= data.endIndex else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[index + i]) << (8 * i)
        }
        index += 4
        return value
    }

    public mutating func readFixed64() -> UInt64? {
        guard index + 8 <= data.endIndex else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[index + i]) << (8 * i)
        }
        index += 8
        return value
    }

    public mutating func readLengthDelimited() -> Data? {
        guard let length = readVarint(), length <= UInt64(data.count) else { return nil }
        let count = Int(length)
        guard index + count <= data.endIndex else { return nil }
        let sub = data.subdata(in: index..<(index + count))
        index += count
        return sub
    }

    public mutating func readString() -> String? {
        guard let bytes = readLengthDelimited() else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    // MARK: - Tags

    /// Reads a field key. Returns `(fieldNumber, wireType)`, or nil at end of
    /// input or on a malformed key.
    public mutating func readTag() -> (field: Int, wireType: Int)? {
        guard let raw = readVarint() else { return nil }
        let fieldNumber = Int(raw >> 3)
        let wireType = Int(raw & 0x7)
        guard fieldNumber > 0 else { return nil }
        return (fieldNumber, wireType)
    }

    /// Skips a field of the given wire type so an unknown field never stalls the
    /// cursor.
    public mutating func skip(wireType: Int) {
        switch wireType {
        case 0: _ = readVarint()
        case 1: _ = readFixed64()
        case 2: _ = readLengthDelimited()
        case 5: _ = readFixed32()
        default: break
        }
    }

    /// Reads a length-delimited field and returns a new decoder over its bytes,
    /// for decoding a nested message.
    public mutating func readMessage() -> ProtobufDecoder? {
        guard let bytes = readLengthDelimited() else { return nil }
        return ProtobufDecoder(bytes)
    }
}
