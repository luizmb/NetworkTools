import Core
import FP

/// Intermediate value produced by `Route ~> DecoderResult`.
/// Attach a handler via a second `~>` to produce a `Router`.
public struct TypedRoute<URLParams: Decodable, QueryParams: Decodable, Body: Decodable>: @unchecked Sendable {
    let route: Route<URLParams, QueryParams>
    let bodyDecoder: DecoderResult<Body>
}
