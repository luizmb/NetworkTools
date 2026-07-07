// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

/// A cross-platform HTTP requester: a **pure function** from a request to its (async) response.
///
/// `HTTPRequester` is deliberately a plain function wrapper — `URLRequest` is an ordinary,
/// deterministic value (a DTO), not a system/IO injection, so there is no reason to model it as a
/// `Reader`. It is the ReactiveConcurrency counterpart of the Combine-based ``Requester``:
///
/// ```
/// Combine:  @Sendable (URLRequest) -> AnyPublisher<(Data, HTTPURLResponse), HTTPError>
/// RC:       @Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>
/// ```
///
/// A *decorator* is an `Endo` over this type — `@Sendable (HTTPRequester) -> HTTPRequester` —
/// so overriding, recording and replaying all compose by plain function composition, independent of
/// the underlying reactive stack.
public struct HTTPRequester: FunctionWrapper, Sendable {
    /// The raw HTTP response pair produced for a request.
    public typealias Response = Result<(Data, HTTPURLResponse), HTTPError>

    public let run: @Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>

    public init(_ run: @escaping @Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>) {
        self.run = run
    }

    public func callAsFunction(_ request: URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError> {
        run(request)
    }
}

// Each decorator (`overriding`, `recording`, `replaying`, `delaying`) is an `Endo<HTTPRequester>` — a
// callable value. Apply one by calling it on a base: `overriding(rules)(base)`. Layer several by
// nesting, which keeps the order of execution explicit and reads inside-out (base first):
//
//     delaying(.seconds(3), when: .path("/slow"), clock: clock)(   // …then delay the result
//         overriding(mocks)(                                       // base is overridden first…
//             base
//         )
//     )
