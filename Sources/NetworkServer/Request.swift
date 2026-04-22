import Core
import Foundation
import FP
import NIOHTTP1

public struct Request: Sendable {
    public let method: HTTPMethod
    public let uri: String
    public let body: Data

    public init(
        method: HTTPMethod,
        uri: String,
        body: Data
    ) {
        self.method     = method
        self.uri        = uri
        self.body       = body
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

    /// Decodes the request body using the given factory into the given `Decodable` type.
    public func decodeBody<T: Decodable>(as _: T.Type = T.self) -> Reader<DataDecoderFactory, Result<T, DecodingError>> {
        Reader { factory in factory.dataDecoder(for: T.self).run(body) }
    }
}
