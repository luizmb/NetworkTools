import Core
import Foundation

/// Decodes the request body into `Body` after a route has matched.
/// Failure returns HTTP 400; success produces a fully typed `TypedRequest`.
public struct RequestDecoder<URLParams, QueryParams, Body: Decodable>: Sendable {
    public init() {}

    func decode(_ matched: MatchedRoute<URLParams, QueryParams>) -> Result<TypedRequest<URLParams, QueryParams, Body>, ResponseError> {
        let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
        return DecoderResult<Body>.json
            .run(bodyData)
            .map { TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: $0, raw: matched.raw) }
            .mapError { .badRequest($0.localizedDescription) }
    }
}
