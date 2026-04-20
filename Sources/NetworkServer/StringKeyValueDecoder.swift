import Foundation

// MARK: - Decoder

struct StringKeyValueDecoder: Decoder {
    let params: [String: String]
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(params: [String: String], codingPath: [any CodingKey] = []) {
        self.params = params
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(StringKeyedContainer(params: params, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Arrays are not supported in string-keyed parameters"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Single-value root is not supported in string-keyed parameters"))
    }
}

// MARK: - Keyed container

struct StringKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let params: [String: String]
    var codingPath: [any CodingKey]
    var allKeys: [Key] { params.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { params[key.stringValue] != nil }

    func decodeNil(forKey key: Key) throws -> Bool { !contains(key) }

    private func stringValue(forKey key: Key) throws -> String {
        guard let v = params[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
                debugDescription: "Key '\(key.stringValue)' not found"))
        }
        return v
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try stringValue(forKey: key)
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let s = try stringValue(forKey: key)
        switch s.lowercased() {
        case "true",  "1", "yes": return true
        case "false", "0", "no":  return false
        default:
            throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath + [key],
                debugDescription: "Cannot convert '\(s)' to Bool"))
        }
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let s = try stringValue(forKey: key)
        guard let v = Double(s) else {
            throw DecodingError.typeMismatch(Double.self, .init(codingPath: codingPath + [key],
                debugDescription: "Cannot convert '\(s)' to Double"))
        }
        return v
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        let s = try stringValue(forKey: key)
        guard let v = Float(s) else {
            throw DecodingError.typeMismatch(Float.self, .init(codingPath: codingPath + [key],
                debugDescription: "Cannot convert '\(s)' to Float"))
        }
        return v
    }

    func decode(_ type: Int.Type,    forKey key: Key) throws -> Int    { try decodeFixedWidth(forKey: key) }
    func decode(_ type: Int8.Type,   forKey key: Key) throws -> Int8   { try decodeFixedWidth(forKey: key) }
    func decode(_ type: Int16.Type,  forKey key: Key) throws -> Int16  { try decodeFixedWidth(forKey: key) }
    func decode(_ type: Int32.Type,  forKey key: Key) throws -> Int32  { try decodeFixedWidth(forKey: key) }
    func decode(_ type: Int64.Type,  forKey key: Key) throws -> Int64  { try decodeFixedWidth(forKey: key) }
    func decode(_ type: UInt.Type,   forKey key: Key) throws -> UInt   { try decodeFixedWidth(forKey: key) }
    func decode(_ type: UInt8.Type,  forKey key: Key) throws -> UInt8  { try decodeFixedWidth(forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeFixedWidth(forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeFixedWidth(forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeFixedWidth(forKey: key) }

    private func decodeFixedWidth<T: FixedWidthInteger>(forKey key: Key) throws -> T {
        let s = try stringValue(forKey: key)
        guard let v = T(s) else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: codingPath + [key],
                debugDescription: "Cannot convert '\(s)' to \(T.self)"))
        }
        return v
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let s = try stringValue(forKey: key)
        return try T(from: StringSingleValueDecoder(value: s, codingPath: codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [key],
            debugDescription: "Nested containers are not supported in string-keyed parameters"))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [key],
            debugDescription: "Arrays are not supported in string-keyed parameters"))
    }

    func superDecoder() throws -> any Decoder {
        StringKeyValueDecoder(params: params, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        StringKeyValueDecoder(params: params, codingPath: codingPath + [key])
    }
}

// MARK: - Single-value decoder (for UUID, RawRepresentable, etc.)

struct StringSingleValueDecoder: Decoder {
    let value: String
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath,
            debugDescription: "Expected a single string value, not a keyed container"))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath,
            debugDescription: "Expected a single string value, not an array"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        StringSingleValueContainer(value: value, codingPath: codingPath)
    }
}

struct StringSingleValueContainer: SingleValueDecodingContainer {
    let value: String
    var codingPath: [any CodingKey]

    func decodeNil() -> Bool { false }
    func decode(_ type: String.Type) throws -> String { value }

    func decode(_ type: Bool.Type) throws -> Bool {
        switch value.lowercased() {
        case "true",  "1", "yes": return true
        case "false", "0", "no":  return false
        default:
            throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath,
                debugDescription: "Cannot convert '\(value)' to Bool"))
        }
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let v = Double(value) else {
            throw DecodingError.typeMismatch(Double.self, .init(codingPath: codingPath,
                debugDescription: "Cannot convert '\(value)' to Double"))
        }
        return v
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let v = Float(value) else {
            throw DecodingError.typeMismatch(Float.self, .init(codingPath: codingPath,
                debugDescription: "Cannot convert '\(value)' to Float"))
        }
        return v
    }

    func decode(_ type: Int.Type)    throws -> Int    { try decodeFixedWidth() }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeFixedWidth() }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeFixedWidth() }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeFixedWidth() }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeFixedWidth() }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeFixedWidth() }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeFixedWidth() }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeFixedWidth() }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeFixedWidth() }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeFixedWidth() }

    private func decodeFixedWidth<T: FixedWidthInteger>() throws -> T {
        guard let v = T(value) else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: codingPath,
                debugDescription: "Cannot convert '\(value)' to \(T.self)"))
        }
        return v
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: StringSingleValueDecoder(value: value, codingPath: codingPath))
    }
}
