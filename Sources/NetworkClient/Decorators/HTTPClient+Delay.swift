// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

public extension HTTPClient {
    /// Adds artificial latency to matching responses — for testing spinners, timeouts and races.
    ///
    /// The `clock` is injected (a Hourglass conformance flows in via ReactiveConcurrency); the library
    /// never constructs one. Pass a `ContinuousClock` at the composition root, or an `ImmediateClock` /
    /// `TestClock` in tests. Wrap whatever you want to slow down — a live client or a mock.
    ///
    /// ```swift
    /// // Serve /slow from a mock, three seconds late (delay wraps the override):
    /// HTTPClient.delay(.seconds(3), when: .path("/slow"), clock: ContinuousClock())(
    ///     HTTPClient.override(on: .path("/slow"), use: .const(.ok(body: page)))(base)
    /// )
    /// ```
    static func delay(
        _ interval: Duration,
        when match: RequestMatch = .any,
        clock: some Clock<Duration> & Sendable
    ) -> Endo<HTTPClient> {
        Endo { base in
            HTTPClient { request in
                let response = base(request)
                return match(request) ? response.delay(for: interval, clock: clock) : response
            }
        }
    }
}
