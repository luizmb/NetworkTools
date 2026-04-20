#if canImport(Combine)
import Combine
import Foundation
import FP

public extension URLSession {
    /// Wraps `URLSession.dataTaskPublisher` as a `Requester`, mapping both the network
    /// error and the missing-`HTTPURLResponse` case into `HTTPError`.
    var requester: Requester {
        Requester { [self] request in
            dataTaskPublisher(for: request)
                .mapError(HTTPError.network)
                .flatMap { data, response in
                    Result.zip(
                        .success(data),
                        (response as? HTTPURLResponse).map(Result.success)
                            ?? .failure(HTTPError.network(URLError(.badServerResponse)))
                    )
                    .publisher
                    .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
    }
}
#endif
