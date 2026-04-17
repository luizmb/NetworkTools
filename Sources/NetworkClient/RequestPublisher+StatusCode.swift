import Combine
import Foundation

// MARK: - Status code validation

public extension RequestPublisher where A == (Data, HTTPURLResponse) {

    /// Validates that the response status code is in the 2xx range.
    /// Fails with `.badStatus` otherwise, attaching the raw body for diagnostics.
    func validateStatusCode() -> RequestPublisher<Data> {
        RequestPublisher<Data> { request in
            run(request).flatMap { data, response -> AnyPublisher<Data, HTTPError> in
                guard 200..<300 ~= response.statusCode else {
                    return Fail(error: HTTPError.badStatus(response.statusCode, data))
                        .eraseToAnyPublisher()
                }
                return Just(data)
                    .setFailureType(to: HTTPError.self)
                    .eraseToAnyPublisher()
            }.eraseToAnyPublisher()
        }
    }
}
