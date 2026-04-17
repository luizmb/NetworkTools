import Combine
import Foundation

// MARK: - Applicative

public extension RequestPublisher {

    /// Lifts a pure value into `RequestPublisher`, ignoring the `URLRequest`.
    static func pure(_ value: A) -> RequestPublisher<A> {
        RequestPublisher { _ in
            Just(value).setFailureType(to: HTTPError.self).eraseToAnyPublisher()
        }
    }

    /// Applies a request-dependent function to a request-dependent value.
    /// Both are run against the same `URLRequest` and zipped.
    static func apply<B>(_ f: RequestPublisher<(A) -> B>, _ r: RequestPublisher<A>) -> RequestPublisher<B> {
        RequestPublisher<B> { request in
            f.run(request).zip(r.run(request))
                .map { fn, a in fn(a) }
                .eraseToAnyPublisher()
        }
    }

    /// Sequences two publishers against the same request, discarding the left result.
    func seqRight<B>(_ rhs: RequestPublisher<B>) -> RequestPublisher<B> {
        RequestPublisher<B> { request in
            self.run(request).zip(rhs.run(request))
                .map { _, b in b }
                .eraseToAnyPublisher()
        }
    }

    /// Sequences two publishers against the same request, discarding the right result.
    func seqLeft<B>(_ rhs: RequestPublisher<B>) -> RequestPublisher<A> {
        RequestPublisher<A> { request in
            self.run(request).zip(rhs.run(request))
                .map { a, _ in a }
                .eraseToAnyPublisher()
        }
    }
}
