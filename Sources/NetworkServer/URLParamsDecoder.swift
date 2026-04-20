import Foundation

/// Decodes a `Decodable` value from URL path parameters (e.g. `["id": "42"]`).
///
/// Missing required keys throw, which the route interprets as "no match".
/// Missing optional keys decode as `nil`.
public enum URLParamsDecoder {
    public static func decode<T: Decodable>(_ type: T.Type = T.self, from params: [String: String]) -> Result<T, Error> {
        Result { try T(from: StringKeyValueDecoder(params: params)) }
    }
}
