import Combine
import Foundation
import NIOHTTP1

// MARK: - Route builder

/// Builds a `RouteMatcher` for an async handler.
public func route(
    _ method: HTTPMethod,
    _ pattern: String,
    _ handler: @escaping (Request) -> AnyPublisher<Response, Never>
) -> RouteMatcher {
    { request in
        guard request.method == method,
              let params = matchPath(request.path, against: pattern)
        else { return nil }
        var req = request
        req.pathParams = params
        return handler(req)
    }
}

/// Convenience overload for sync handlers — wraps the result in `Just`.
public func route(
    _ method: HTTPMethod,
    _ pattern: String,
    _ handler: @escaping (Request) -> Response
) -> RouteMatcher {
    route(method, pattern) { req in
        Just(handler(req)).eraseToAnyPublisher()
    }
}

/// Returns the first matched route's publisher, or a `.notFound` response.
public func firstMatch(_ matchers: [RouteMatcher]) -> Handler {
    Handler { request in
        matchers.lazy.compactMap { $0(request) }.first
            ?? Just(.notFound).eraseToAnyPublisher()
    }
}

// MARK: - Path matching

/// Matches `path` against a `pattern` like `/albums/:id/photos/:photoId`.
/// Returns the captured params dict on success, `nil` on mismatch.
private func matchPath(_ path: String, against pattern: String) -> [String: String]? {
    let pathParts    = path.split(separator: "/", omittingEmptySubsequences: true)
    let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: true)
    guard pathParts.count == patternParts.count else { return nil }

    let pairs = Array(zip(pathParts, patternParts))

    // Fail fast on any literal segment mismatch.
    guard !pairs.contains(where: { seg, tok in !tok.hasPrefix(":") && seg != tok }) else {
        return nil
    }

    // Collect named captures from parameter segments.
    return pairs.reduce(into: [:]) { params, pair in
        let (seg, tok) = pair
        if tok.hasPrefix(":") { params[String(tok.dropFirst())] = String(seg) }
    }
}
