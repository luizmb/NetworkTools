// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ReactiveConcurrency

public extension Publisher where Output == (Data, HTTPURLResponse), Failure == HTTPError {
    /// Validates that the response status code is in the 2xx range, forwarding the raw `Data`.
    /// Fails with `.badStatus` otherwise, attaching the body for diagnostics.
    func validateStatusCode() -> Publisher<Data, HTTPError> {
        flatMap { pair -> Publisher<Data, HTTPError> in
            let (data, response) = pair
            return 200 ..< 300 ~= response.statusCode
                ? Publisher<Data, HTTPError>.just(data)
                : Publisher<Data, HTTPError>.fail(.badStatus(response.statusCode, data))
        }
    }
}
