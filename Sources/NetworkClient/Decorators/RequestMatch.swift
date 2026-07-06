// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A predicate that decides whether a `URLRequest` matches — the shared "which request?" atom used
/// by the override and replay decorators.
///
/// At heart it is just `@Sendable (URLRequest) -> Bool`. The value type adds composable constructors
/// (method, host, path, query, header, regex) and combinators (`&&`, `||`, `!`, ``all(_:)``,
/// ``any(_:)``) so simple or precise matchers can be assembled without hand-writing closures.
///
/// ```swift
/// let m = .method("GET") && .path("/users") && .query("page", "2")
/// let stale = .host("staging.example.com") || .host("dev.example.com")
/// ```
public struct RequestMatch: Sendable {
    public let matches: @Sendable (URLRequest) -> Bool

    public init(_ matches: @escaping @Sendable (URLRequest) -> Bool) {
        self.matches = matches
    }

    public func callAsFunction(_ request: URLRequest) -> Bool { matches(request) }
}

// MARK: - Constructors

public extension RequestMatch {
    /// Matches every request.
    static let any = RequestMatch { _ in true }

    /// Matches no request.
    static let none = RequestMatch { _ in false }

    /// Case-insensitive HTTP method (defaults to `GET` when the request has none).
    static func method(_ method: String) -> RequestMatch {
        RequestMatch { (($0.httpMethod ?? "GET").caseInsensitiveCompare(method)) == .orderedSame }
    }

    /// Case-insensitive host.
    static func host(_ host: String) -> RequestMatch {
        RequestMatch { $0.url?.host?.caseInsensitiveCompare(host) == .orderedSame }
    }

    /// Exact URL path, tolerant of a single trailing slash (`/users` matches `/users/`).
    static func path(_ path: String) -> RequestMatch {
        let wanted = normalizedPath(path)
        return RequestMatch { normalizedPath($0.url?.path ?? "") == wanted }
    }

    /// URL path prefix (e.g. `.pathPrefix("/api/v1")`).
    static func pathPrefix(_ prefix: String) -> RequestMatch {
        RequestMatch { ($0.url?.path ?? "").hasPrefix(prefix) }
    }

    /// URL path matches a regular expression (Foundation `.regularExpression`).
    static func pathRegex(_ pattern: String) -> RequestMatch {
        regex(pattern) { $0.url?.path }
    }

    /// Exact absolute URL string.
    static func url(_ url: URL) -> RequestMatch {
        RequestMatch { $0.url == url }
    }

    /// Absolute URL string matches a regular expression.
    static func urlRegex(_ pattern: String) -> RequestMatch {
        regex(pattern) { $0.url?.absoluteString }
    }

    /// Has a query item with `name` and exactly `value` (order-insensitive).
    static func query(_ name: String, _ value: String) -> RequestMatch {
        RequestMatch { queryItems($0).contains { $0.name == name && $0.value == value } }
    }

    /// Has a query item named `name` (any value).
    static func query(_ name: String) -> RequestMatch {
        RequestMatch { queryItems($0).contains { $0.name == name } }
    }

    /// Has a request header `name` with exactly `value` (case-insensitive header name).
    static func header(_ name: String, _ value: String) -> RequestMatch {
        RequestMatch { $0.value(forHTTPHeaderField: name) == value }
    }

    /// Has a request header named `name` (any value).
    static func header(_ name: String) -> RequestMatch {
        RequestMatch { $0.value(forHTTPHeaderField: name) != nil }
    }

    /// Matches on the raw request body.
    static func body(_ predicate: @escaping @Sendable (Data?) -> Bool) -> RequestMatch {
        RequestMatch { predicate($0.httpBody) }
    }

    /// Escape hatch for an arbitrary predicate.
    static func custom(_ predicate: @escaping @Sendable (URLRequest) -> Bool) -> RequestMatch {
        RequestMatch(predicate)
    }
}

// MARK: - Combinators

public extension RequestMatch {
    /// Logical AND.
    static func && (lhs: RequestMatch, rhs: RequestMatch) -> RequestMatch {
        RequestMatch { lhs($0) && rhs($0) }
    }

    /// Logical OR.
    static func || (lhs: RequestMatch, rhs: RequestMatch) -> RequestMatch {
        RequestMatch { lhs($0) || rhs($0) }
    }

    /// Negation.
    static prefix func ! (m: RequestMatch) -> RequestMatch {
        RequestMatch { !m($0) }
    }

    /// True only when every matcher matches (AND). Empty list matches everything.
    static func all(_ matchers: [RequestMatch]) -> RequestMatch {
        RequestMatch { request in matchers.allSatisfy { $0(request) } }
    }

    /// True when any matcher matches (OR). Empty list matches nothing.
    static func any(_ matchers: [RequestMatch]) -> RequestMatch {
        RequestMatch { request in matchers.contains { $0(request) } }
    }
}

// MARK: - Helpers

private func normalizedPath(_ path: String) -> String {
    path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

private func queryItems(_ request: URLRequest) -> [URLQueryItem] {
    request.url
        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems ?? []
}

private func regex(_ pattern: String, _ field: @escaping @Sendable (URLRequest) -> String?) -> RequestMatch {
    RequestMatch { request in
        guard let value = field(request) else { return false }
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
