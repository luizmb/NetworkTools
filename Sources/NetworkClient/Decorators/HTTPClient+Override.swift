// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP

public extension HTTPClient {
    /// Routes matching requests to another client (typically a `.const` mock), short-circuiting the
    /// base. Unmatched requests pass through to the wrapped client. Layer multiple overrides by nesting.
    ///
    /// ```swift
    /// HTTPClient.override(on: .method("GET") && .path("/currencies"),
    ///                     use: .const(.json(["BRL", "MXN"], encoder: JSONEncoder())))(base)
    /// ```
    static func override(on match: RequestMatch, use client: HTTPClient) -> Endo<HTTPClient> {
        override(on: match) { _ in client }
    }

    /// Routes matching requests to a **request-derived** client — build the response from the request:
    ///
    /// ```swift
    /// HTTPClient.override(on: .path("/echo")) { request in
    ///     .const(.ok() <> .withStatus(200) <> .withHeaders(request.allHTTPHeaderFields ?? [:]))
    /// }(base)
    /// ```
    static func override(
        on match: RequestMatch,
        use client: @escaping @Sendable (URLRequest) -> HTTPClient
    ) -> Endo<HTTPClient> {
        Endo { base in
            HTTPClient { request in
                match(request) ? client(request)(request) : base(request)
            }
        }
    }
}
