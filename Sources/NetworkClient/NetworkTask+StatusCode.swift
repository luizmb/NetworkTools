import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP

// MARK: - Status code validation

private func _validateStatusCode(_ data: Data, _ response: HTTPURLResponse) -> NetworkTask<Data> {
    guard 200..<300 ~= response.statusCode else {
        return ZIO { _ in DeferredTask { .failure(.badStatus(response.statusCode, data)) } }
    }
    return .pure(data)
}

public extension ZIO where Env == URLRequest, Success == (Data, HTTPURLResponse), Failure == HTTPError {
    /// Validates that the response status code is in the 2xx range.
    /// Fails with `.badStatus` otherwise, attaching the raw body for diagnostics.
    func validateStatusCode() -> NetworkTask<Data> {
        flatMap { _validateStatusCode($0, $1) }
    }
}
