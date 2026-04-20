import Core
import FP
import Foundation

/// Decodes the request body into `Body` after a route has matched.
/// Failure returns HTTP 400; success produces a fully typed `TypedRequest`.
public struct RequestDecoder<URLParams, QueryParams, Body: Decodable>: @unchecked Sendable {
    private let bodyDecoder: DecoderResult<Body>

    public init(_ bodyDecoder: DecoderResult<Body>) {
        self.bodyDecoder = bodyDecoder
    }

    func decode(_ matched: MatchedRoute<URLParams, QueryParams>) -> Result<TypedRequest<URLParams, QueryParams, Body>, ResponseError> {
        let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
        return bodyDecoder
            .run(bodyData)
            .map { TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: $0, raw: matched.raw) }
            .mapError { .badRequest($0.localizedDescription) }
    }
}

extension RequestDecoder where Body == Empty {
    public init() {
        self.init(DecoderResult { _ in .success(.value) })
    }
}

extension RequestDecoder {
    public static var json: Reader<JSONDecoder, Self> {
        Reader { Self(DecoderResult<Body>.json.runReader($0)) }
    }
}
