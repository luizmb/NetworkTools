// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOCore)
import Foundation
import FP
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
    private let pathPattern: PathPattern

    public init(_ method: HTTPMethod, _ pattern: String) {
        self.method = method
        self.pattern = pattern
        pathPattern = PathPattern(pattern)
    }

    public func match(_ raw: Request) -> Reader<DictionaryDecoderFactory, Result<MatchedRoute<URLParams, QueryParams>, ResponseError>> {
        Reader { env in
            guard raw.method == method,
                  let pathParams = pathPattern.match(raw.path),
                  case let .success(urlParams) = env.dictionaryDecoder(for: URLParams.self).run(pathParams)
            else { return .failure(.notFound) }

            switch env.dictionaryDecoder(for: QueryParams.self).run(raw.queryParams) {
            case let .success(queryParams):
                return .success(MatchedRoute(urlParams: urlParams, queryParams: queryParams, raw: raw))
            case let .failure(error):
                return .failure(.badRequest(error.localizedDescription))
            }
        }
    }
}

// MARK: - Path matching

/// A route pattern split into segments once, so matching a request only walks the request's path.
struct PathPattern: Sendable {
    private enum Segment: Sendable {
        case literal(Substring)
        case parameter(String)
    }

    private let segments: [Segment]

    init(_ pattern: String) {
        segments = pattern.split(separator: "/", omittingEmptySubsequences: true).map { token in
            token.hasPrefix(":") ? .parameter(String(token.dropFirst())) : .literal(token)
        }
    }

    // swiftlint:disable:next discouraged_optional_collection
    func match(_ path: String) -> [String: String]? {
        var params: [String: String] = [:]
        var index = 0
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            guard index < segments.count else { return nil }
            switch segments[index] {
            case let .literal(literal):
                guard part == literal else { return nil }
            case let .parameter(name):
                params[name] = String(part)
            }
            index += 1
        }
        return index == segments.count ? params : nil
    }
}

// swiftlint:disable:next discouraged_optional_collection
func matchPath(_ path: String, against pattern: String) -> [String: String]? {
    PathPattern(pattern).match(path)
}
#endif
