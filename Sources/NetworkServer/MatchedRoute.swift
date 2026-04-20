public struct MatchedRoute<URLParams, QueryParams> {
    public let urlParams: URLParams
    public let queryParams: QueryParams
    public let raw: Request
}
