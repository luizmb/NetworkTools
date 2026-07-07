// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

/// What a replay decorator does when a request matches no (remaining) recording.
public enum ReplayFallback: Sendable {
    /// Pass through to the wrapped requester (e.g. hit the live network, or a 404 stub underneath).
    case base
    /// Serve a synthetic `404 Not Found` with an empty body.
    case notFound
    /// Fail with a specific error.
    case failure(HTTPError)
}

public extension HTTPRequester {
    /// Replays recorded responses from a ``RequestPlayback`` source, consuming each recording once.
    ///
    /// For each request the first not-yet-consumed matching recording is served — its status, headers
    /// **and** body (unlike ARQ, headers are replayed). Requests with no matching recording take the
    /// `fallback`. Matching reuses the recorded request attributes via `matching` (default: method +
    /// absolute URL); compose with a ``RequestMatch`` upstream if you want to scope which requests are
    /// eligible at all.
    static func replaying(
        _ playback: RequestPlayback,
        matching: @escaping @Sendable (URLRequest, RecordedExchange) -> Bool = RecordedExchange.matchesMethodAndURL,
        fallback: ReplayFallback = .base
    ) -> Endo<HTTPRequester> {
        Endo { base in
            HTTPRequester { request in
                let consume = Publisher<RecordedExchange?, HTTPError>.future {
                    .success(await playback.consume(for: request, matching: matching))
                }
                return consume.flatMap { recorded in
                    if let recorded {
                        let response: ReactiveConcurrency.Publisher<(Data, HTTPURLResponse), HTTPError> =
                            recorded.asResponse().publisher
                        return response
                    }
                    switch fallback {
                    case .base:
                        return base(request)
                    case .notFound:
                        let notFound: ReactiveConcurrency.Publisher<(Data, HTTPURLResponse), HTTPError> =
                            makeResponse(request: request, status: 404, headers: [:], body: Data()).publisher
                        return notFound
                    case let .failure(error):
                        return Publisher.fail(error)
                    }
                }
            }
        }
    }
}
