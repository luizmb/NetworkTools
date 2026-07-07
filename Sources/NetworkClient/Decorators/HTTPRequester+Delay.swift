// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import ReactiveConcurrency

public extension HTTPRequester {
    /// Adds artificial latency to matching responses — for testing spinners, timeouts and races.
    ///
    /// The `clock` is injected (a Hourglass conformance flows in via ReactiveConcurrency); the library
    /// never constructs one. Pass a `ContinuousClock` at the composition root, or an `ImmediateClock`
    /// / `TestClock` in tests for determinism.
    ///
    /// Compose it around whatever you want to slow down — the real network, or a mock. Order expresses
    /// intent: put `delaying` *outside* `overriding` to delay a mocked response, or wrap the base
    /// requester directly to delay live traffic.
    ///
    /// ```swift
    /// // Serve /slow from a mock, but three seconds late:
    /// base.applying(HTTPRequester.delaying(.seconds(3), when: .path("/slow"), clock: ContinuousClock())
    ///                 <> HTTPRequester.overriding(mocks))
    /// ```
    ///
    /// - Parameters:
    ///   - interval: how long to delay each matching response.
    ///   - match: which requests to slow down (default: all).
    ///   - clock: the injected clock the delay runs on.
    static func delaying(
        _ interval: Duration,
        when match: RequestMatch = .any,
        clock: some Clock<Duration> & Sendable
    ) -> Endo<HTTPRequester> {
        Endo { base in
            HTTPRequester { request in
                let response = base(request)
                return match(request) ? response.delay(for: interval, clock: clock) : response
            }
        }
    }
}
