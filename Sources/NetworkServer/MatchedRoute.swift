public struct MatchedRoute<URLParams: Sendable, QueryParams: Sendable>: Sendable {
    public let urlParams: URLParams
    public let queryParams: QueryParams
    public let raw: Request
}
