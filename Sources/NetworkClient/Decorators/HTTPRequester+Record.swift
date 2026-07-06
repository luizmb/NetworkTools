// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import ReactiveConcurrency

public extension HTTPRequester {
    /// Records every successful exchange to a ``RecordStore`` as it flows through, then forwards it unchanged.
    ///
    /// The response is teed, not intercepted — the caller still gets the real result. Each recording
    /// is persisted through the store's actor (serialized, no read-modify-write race). Wrap the
    /// override decorator *inside* this one (`recording(...) <> overriding(...)`, applied
    /// outer-to-inner) if you also want mocked responses captured.
    ///
    /// - Parameters:
    ///   - store: where exchanges are persisted.
    ///   - now: optional timestamp source (inject `{ Date() }` at the composition root). When `nil`,
    ///     exchanges are recorded without a date, keeping the decorator pure by default.
    static func recording(to store: RecordStore, now: (@Sendable () -> Date)? = nil) -> Endo<HTTPRequester> {
        Endo { base in
            HTTPRequester { request in
                base(request).flatMap { pair in
                    let (data, response) = pair
                    return Publisher.future {
                        let exchange = RecordedExchange(request: request, responseBody: data, response: response, date: now?())
                        _ = await store.append(exchange)
                        return .success((data, response))
                    }
                }
            }
        }
    }
}
