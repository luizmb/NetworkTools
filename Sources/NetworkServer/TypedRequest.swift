import Foundation
import NIOHTTP1

/// A request whose URL parameters, query parameters, and body have been decoded
/// into typed values. Access the original `Request` via `.raw` for method, URI, headers, etc.
public struct TypedRequest<URLParams, QueryParams, Body>: @unchecked Sendable {
    public let urlParams: URLParams
    public let queryParams: QueryParams
    public let body: Body
    public let raw: Request
}
