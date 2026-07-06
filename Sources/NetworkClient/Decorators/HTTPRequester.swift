// SPDX-License-Identifier: Apache-2.0

import Foundation
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

// MARK: - Applying a transform

public extension HTTPRequester {
    /// Applies a pure requester transform. Build transforms with `overriding` / `recording` /
    /// `replaying`, composing several with `<>`: `base.applying(recording(to: store) <> overriding(mocks))`.
    func applying(_ transform: Endo<HTTPRequester>) -> HTTPRequester {
        transform.runEndo(self)
    }
}
