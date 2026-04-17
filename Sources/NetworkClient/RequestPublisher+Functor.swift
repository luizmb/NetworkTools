import Combine
import Foundation

// MARK: - Functor

public extension RequestPublisher {

    /// Transforms the output value; the same `URLRequest` is threaded through unchanged.
    func map<B>(_ f: @escaping (A) -> B) -> RequestPublisher<B> {
        RequestPublisher<B> { request in run(request).map(f).eraseToAnyPublisher() }
    }

    /// Curried fmap for point-free composition.
    static func fmap<B>(_ f: @escaping (A) -> B) -> (RequestPublisher<A>) -> RequestPublisher<B> {
        { $0.map(f) }
    }

    /// Replaces the output with a constant value.
    func replace<B>(with value: B) -> RequestPublisher<B> {
        map { _ in value }
    }

    /// Maps the failure side of the underlying publisher.
    func mapError(_ f: @escaping (HTTPError) -> HTTPError) -> RequestPublisher<A> {
        RequestPublisher { request in run(request).mapError(f).eraseToAnyPublisher() }
    }
}
