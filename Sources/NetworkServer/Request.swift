import Foundation
import NIOHTTP1

public struct Request: Sendable {
    public let method: HTTPMethod
    public let uri: String
    public let body: Data
    public var pathParams: [String: String]

    public init(
        method: HTTPMethod,
        uri: String,
        body: Data,
        pathParams: [String: String] = [:]
    ) {
        self.method     = method
        self.uri        = uri
        self.body       = body
        self.pathParams = pathParams
    }

    public var path: String {
        String(uri.prefix(while: { $0 != "?" }))
    }

    public var queryParams: [String: String] {
        guard let query = uri.split(separator: "?", maxSplits: 1).dropFirst().first else {
            return [:]
        }
        return String(query)
            .split(separator: "&")
            .reduce(into: [:]) { acc, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first?.removingPercentEncoding,
                      let val = parts.dropFirst().first?.removingPercentEncoding
                else { return }
                acc[key] = val
            }
    }

    /// Decodes the request body as JSON into the given `Decodable` type.
    public func decodeBody<T: Decodable>(as _: T.Type = T.self) -> Result<T, DecodingError> {
        Result { try JSONDecoder().decode(T.self, from: body) }
            .mapError {
                $0 as? DecodingError
                    ?? DecodingError.dataCorrupted(.init(
                        codingPath: [],
                        debugDescription: "Unknown decoding error: \($0)"
                    ))
            }
    }
}
