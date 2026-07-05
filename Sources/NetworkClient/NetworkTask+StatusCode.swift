import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency
import ReactiveConcurrencyTransformers

// MARK: - Status code validation

private func _validateStatusCode(_ data: Data, _ response: HTTPURLResponse) -> NetworkTask<Data> {
    guard 200..<300 ~= response.statusCode else {
        return Reader { _ in Publisher.future { .failure(.badStatus(response.statusCode, data)) } }
    }
    return Reader { _ in Publisher.pure(data) }
}

public extension Reader where Environment == URLRequest, Output == Publisher<(Data, HTTPURLResponse), HTTPError> {
    /// Validates that the response status code is in the 2xx range.
    /// Fails with `.badStatus` otherwise, attaching the raw body for diagnostics.
    func validateStatusCode() -> NetworkTask<Data> {
        flatMapT { pair in _validateStatusCode(pair.0, pair.1) }
    }
}
