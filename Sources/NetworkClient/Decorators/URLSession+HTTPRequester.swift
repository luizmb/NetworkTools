// SPDX-License-Identifier: Apache-2.0

import Foundation
import ReactiveConcurrency
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension URLSession {
    /// A live base ``HTTPRequester`` backed by this session — the plain-function (ReactiveConcurrency)
    /// counterpart of ``URLSession/requester`` (Combine). Layer `overriding`, `recording`, or
    /// `replaying` onto it with `applying`:
    ///
    /// ```swift
    /// let client = URLSession.shared.httpRequester.applying(HTTPRequester.overriding(rules, clock: ContinuousClock()))
    /// ```
    var httpRequester: HTTPRequester {
        HTTPRequester { [self] request in
            Publisher.future {
                do {
                    let (data, response) = try await self.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        return .failure(.network(URLError(.badServerResponse)))
                    }
                    return .success((data, http))
                } catch {
                    return .failure(.network(error))
                }
            }
        }
    }
}
