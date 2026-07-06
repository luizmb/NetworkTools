// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import Hourglass
import ReactiveConcurrency

/// A single override: a request predicate paired with the response to serve when it matches.
public struct Rule: Sendable {
    public let match: RequestMatch
    public let response: StubResponse

    public init(_ match: RequestMatch, respond response: StubResponse) {
        self.match = match
        self.response = response
    }
}

public extension HTTPRequester {
    /// Overrides matching requests with canned responses, short-circuiting the network entirely.
    ///
    /// Rules are tried in order; the first whose ``RequestMatch`` matches wins and its
    /// ``StubResponse`` is served (a synthetic 200/empty seed transformed by the stub). Requests
    /// that match no rule pass through to the wrapped requester untouched.
    ///
    /// The `clock` is injected (a Hourglass conformance flows in via ReactiveConcurrency) so `withDelay`
    /// is deterministic under test — the library never constructs a clock. Pass a `ContinuousClock` at
    /// the composition root, or an `ImmediateClock` / `TestClock` in tests.
    ///
    /// ```swift
    /// let client = session.httpRequester.applying(HTTPRequester.overriding([
    ///     Rule(.method("GET") && .path("/currencies"), respond: .ok(body: canned)),
    ///     Rule(.pathPrefix("/flaky"),                   respond: .failure(.network(URLError(.timedOut)))),
    /// ], clock: ContinuousClock()))
    /// ```
    static func overriding(_ rules: [Rule], clock: some Clock<Duration> & Sendable) -> Endo<HTTPRequester> {
        Endo { base in
            HTTPRequester { request in
                guard let rule = rules.first(where: { $0.match(request) }) else {
                    return base(request)
                }
                let result = rule.response.response(for: request, incoming: StubResponse.seed(for: request))
                let publisher: ReactiveConcurrency.Publisher<(Data, HTTPURLResponse), HTTPError> = result.publisher
                return rule.response.delay > .zero
                    ? publisher.delay(for: rule.response.delay, clock: clock)
                    : publisher
            }
        }
    }

    /// Convenience for a single override rule.
    static func overriding(
        when match: RequestMatch,
        respond response: StubResponse,
        clock: some Clock<Duration> & Sendable
    ) -> Endo<HTTPRequester> {
        overriding([Rule(match, respond: response)], clock: clock)
    }
}
