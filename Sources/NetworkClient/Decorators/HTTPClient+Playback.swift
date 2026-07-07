// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

public extension HTTPClient {
    /// Replays recorded responses from a ``RequestPlayback`` snapshot, consuming each recording **once**
    /// (in file order, per matcher). Matched requests replay the recorded status, headers and body.
    ///
    /// Requests with no matching (remaining) recording fall through to the wrapped client — so nest a
    /// `.const(.status(404))` base for strict replay, or a live client for replay-or-network.
    ///
    /// ```swift
    /// HTTPClient.playback(snapshot)(HTTPClient.const(.status(404)))   // strict: replay or 404
    /// ```
    static func playback(
        _ source: RequestPlayback,
        matching: @escaping @Sendable (URLRequest, RecordedExchange) -> Bool = RecordedExchange.matchesMethodAndURL
    ) -> Endo<HTTPClient> {
        Endo { base in
            HTTPClient { request in
                let consume = Publisher<RecordedExchange?, HTTPError>.future {
                    .success(await source.consume(for: request, matching: matching))
                }
                return consume.flatMap { recorded in
                    guard let recorded else { return base(request) }
                    let response: Publisher<(Data, HTTPURLResponse), HTTPError> = recorded.asResponse().publisher
                    return response
                }
            }
        }
    }
}
