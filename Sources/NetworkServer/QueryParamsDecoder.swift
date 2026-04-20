import Foundation

/// Decodes a `Decodable` value from URL query parameters (e.g. `["page": "2", "q": "swift"]`).
///
/// Missing required keys throw, which the route converts to HTTP 400.
/// Missing optional keys decode as `nil`.
public enum QueryParamsDecoder {
    public static func decode<T: Decodable>(_ type: T.Type = T.self, from params: [String: String]) -> Result<T, Error> {
        Result { try T(from: StringKeyValueDecoder(params: params)) }
    }
}
