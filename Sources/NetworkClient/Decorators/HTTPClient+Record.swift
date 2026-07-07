// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

public extension HTTPClient {
    /// Records every successful exchange to a ``RecordStore`` as it flows through, then forwards it
    /// unchanged (a tee, not an interception). Each recording is persisted through the store's actor
    /// (serialized, no read-modify-write race). Wrap the override *inside* this to capture mocks too.
    ///
    /// - Parameters:
    ///   - store: where exchanges are persisted.
    ///   - now: optional timestamp source (inject `{ Date() }` at the composition root). When `nil`,
    ///     exchanges are recorded without a date, keeping the decorator pure by default.
    static func record(to store: RecordStore, now: (@Sendable () -> Date)? = nil) -> Endo<HTTPClient> {
        Endo { base in
            HTTPClient { request in
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
