import FP
import Foundation
import NIOHTTP1
/// Matches an incoming request and decodes its URL and query parameters into typed values.
///
/// - `URLParams` is decoded from path segments (`:id`, `:name`, …) using `URLParamsDecoder`.
///   Failure means the route does **not** match — the next route is tried.
/// - `QueryParams` is decoded from the query string using `QueryParamsDecoder`.
///   Failure after a successful URL match returns HTTP 400.
///
/// Use `Empty` for any parameter group that requires no decoding.
/// Body decoding is attached via the `=>` operator when building the router.
///
/// ```swift
/// Route<Empty, Empty>(.GET, "/ping")
/// Route<UserParams, Empty>(.GET, "/users/:id")
/// ```
public struct Route<URLParams: Decodable & Sendable, QueryParams: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    public let pattern: String

    public init(_ method: HTTPMethod, _ pattern: String) {
        self.method  = method
        self.pattern = pattern
    }

    public func match(_ raw: Request) -> Reader<DictionaryDecoderFactory, Result<MatchedRoute<URLParams, QueryParams>, ResponseError>> {
        Reader { env in
            guard raw.method == method,
                let pathParams = matchPath(raw.path, against: pattern),
                case .success(let urlParams) = env.dictionaryDecoder(for: URLParams.self).run(pathParams)
            else { return .failure(.notFound) }

            switch env.dictionaryDecoder(for: QueryParams.self).run(raw.queryParams) {
            case .success(let queryParams):
                return .success(MatchedRoute(urlParams: urlParams, queryParams: queryParams, raw: raw))
            case .failure(let error):
                return .failure(.badRequest(error.localizedDescription))
            }
        }
    }
}

// MARK: - Path matching

// swiftlint:disable:next discouraged_optional_collection
func matchPath(_ path: String, against pattern: String) -> [String: String]? {
    let pathParts    = path.split(separator: "/", omittingEmptySubsequences: true)
    let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: true)
    guard pathParts.count == patternParts.count else { return nil }

    let pairs = Array(zip(pathParts, patternParts))

    guard !pairs.contains(where: { seg, tok in !tok.hasPrefix(":") && seg != tok }) else {
        return nil
    }

    return pairs.reduce(into: [:]) { params, pair in
        let (seg, tok) = pair
        if tok.hasPrefix(":") { params[String(tok.dropFirst())] = String(seg) }
    }
}
