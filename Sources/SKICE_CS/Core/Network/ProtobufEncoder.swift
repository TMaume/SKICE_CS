import Foundation

/// Minimal protobuf wire-format writer.
///
/// Steam's IAuthenticationService expects its request payloads as protobuf
/// messages, transported as a base64 string in the "input_protobuf_encoded"
/// form field. Only the wire types this app needs are implemented, which keeps
/// the package free of any new SPM dependency (ROADMAP ADR-06).
public struct ProtobufEncoder: Sendable {
    public private(set) var data: Data = Data()

    public init() {}

    public var base64String: String {
        data.base64EncodedString()
    }

    public var isEmpty: Bool {
        data.isEmpty
    }

    // MARK: - Scalars

    public mutating func writeVarint(_ value: UInt64) {
        var remaining = value
        while true {
            if remaining < 0x80 {
                data.append(UInt8(remaining))
                return
            }
            data.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
    }

    public mutating func writeTag(_ field: Int, wireType: UInt64) {
        writeVarint((UInt64(field) << 3) | wireType)
    }

    public mutating func writeUInt64(_ field: Int, _ value: UInt64) {
        writeTag(field, wireType: 0)
        writeVarint(value)
    }

    public mutating func writeInt32(_ field: Int, _ value: Int32) {
        writeTag(field, wireType: 0)
        writeVarint(UInt64(bitPattern: Int64(value)))
    }

    public mutating func writeBool(_ field: Int, _ value: Bool) {
        writeTag(field, wireType: 0)
        writeVarint(value ? 1 : 0)
    }

    public mutating func writeFixed64(_ field: Int, _ value: UInt64) {
        writeTag(field, wireType: 1)
        appendLittleEndian(value)
    }

    public mutating func writeFloat(_ field: Int, _ value: Float) {
        writeTag(field, wireType: 5)
        appendLittleEndian(value.bitPattern)
    }

    // MARK: - Length-delimited

    public mutating func writeString(_ field: Int, _ value: String) {
        writeBytes(field, Data(value.utf8))
    }

    public mutating func writeBytes(_ field: Int, _ value: Data) {
        writeTag(field, wireType: 2)
        writeVarint(UInt64(value.count))
        data.append(value)
    }

    public mutating func writeMessage(_ field: Int, _ nested: ProtobufEncoder) {
        writeBytes(field, nested.data)
    }

    // MARK: - Private

    private mutating func appendLittleEndian(_ value: UInt64) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            data.append(contentsOf: raw)
        }
    }

    private mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            data.append(contentsOf: raw)
        }
    }
}
