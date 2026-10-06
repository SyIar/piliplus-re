import Foundation

/// A bounded protobuf wire document. Unchanged fields retain their exact bytes,
/// including unknown fields, when editing server-provided settings.
public struct PiliProtoMessage: Equatable, Sendable {
    public enum DecodeError: Error, Equatable { case tooLarge, truncated, invalidKey, invalidVarint, unsupportedWire }
    public struct Field: Equatable, Sendable {
        public let number: Int
        public let wire: Int
        public let value: Data
        fileprivate let encoded: Data
    }
    public private(set) var fields: [Field] = []
    public init() {}
    public init(data: Data, limit: Int = 8 * 1024 * 1024) throws {
        guard data.count <= limit else { throw DecodeError.tooLarge }
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard fields.count < 65_536 else { throw DecodeError.tooLarge }
            let start = index, key = try Self.varint(bytes, index: &index)
            let number = key >> 3, wire = Int(key & 7)
            guard number > 0, number <= 0x1FFFFFFF else { throw DecodeError.invalidKey }
            let value: Data
            switch wire {
            case 0:
                let start = index
                _ = try Self.varint(bytes, index: &index)
                value = Data(bytes[start..<index])
            case 1, 5:
                let size = wire == 1 ? 8 : 4
                guard size <= bytes.count - index else { throw DecodeError.truncated }
                value = Data(bytes[index..<index + size]); index += size
            case 2:
                let length = try Self.varint(bytes, index: &index)
                guard length <= UInt64(bytes.count - index) else { throw DecodeError.truncated }
                let size = Int(length)
                value = Data(bytes[index..<index + size]); index += size
            default: throw DecodeError.unsupportedWire
            }
            fields.append(Field(number: Int(number), wire: wire, value: value, encoded: Data(bytes[start..<index])))
        }
    }
    public var data: Data { fields.reduce(into: Data()) { $0.append($1.encoded) } }
    public func has(_ field: Int) -> Bool { fields.contains { $0.number == field } }
    public func bytes(_ field: Int) -> Data? { fields.last { $0.number == field && $0.wire == 2 }?.value }
    public func string(_ field: Int) -> String { bytes(field).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    public func integer(_ field: Int) -> Int {
        guard let value = fields.last(where: { $0.number == field && $0.wire == 0 })?.value else { return 0 }
        var index = 0
        guard let value = try? Self.varint([UInt8](value), index: &index), value <= UInt64(Int.max) else { return 0 }
        return Int(value)
    }
    public func message(_ field: Int) throws -> Self { try Self(data: bytes(field) ?? Data()) }
    public func messages(_ field: Int) throws -> [Self] {
        try fields.filter { $0.number == field && $0.wire == 2 }.map { try Self(data: $0.value) }
    }
    public mutating func set(_ field: Int, integer: Int) {
        replace(field, wire: 0, value: Self.encodeVarint(UInt64(bitPattern: Int64(integer))))
    }
    public mutating func set(_ field: Int, string: String) { set(field, bytes: Data(string.utf8)) }
    public mutating func set(_ field: Int, bytes: Data) { replace(field, wire: 2, value: bytes) }
    public mutating func set(_ field: Int, message: Self) { set(field, bytes: message.data) }
    public mutating func set(_ field: Int, messages: [Self]) {
        fields.removeAll { $0.number == field }
        for message in messages { append(field, wire: 2, value: message.data) }
    }
    private mutating func replace(_ field: Int, wire: Int, value: Data) {
        fields.removeAll { $0.number == field }; append(field, wire: wire, value: value)
    }
    private mutating func append(_ field: Int, wire: Int, value: Data) {
        precondition((1...0x1FFFFFFF).contains(field))
        var encoded = Self.encodeVarint(UInt64(field << 3 | wire))
        if wire == 2 { encoded.append(Self.encodeVarint(UInt64(value.count))) }
        encoded.append(value)
        fields.append(Field(number: field, wire: wire, value: value, encoded: encoded))
    }
    private static func varint(_ bytes: [UInt8], index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard index < bytes.count else { throw DecodeError.truncated }
            let byte = bytes[index]; index += 1
            if shift == 63 && byte > 1 { throw DecodeError.invalidVarint }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
        }
        throw DecodeError.invalidVarint
    }
    private static func encodeVarint(_ value: UInt64) -> Data {
        var value = value, data = Data()
        while value >= 0x80 { data.append(UInt8(value & 0x7f) | 0x80); value >>= 7 }
        data.append(UInt8(value)); return data
    }
}
