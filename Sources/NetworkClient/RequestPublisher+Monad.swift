import Combine
import Foundation

// MARK: - Monad

public extension RequestPublisher {

    /// Chains two `RequestPublisher`s, threading the same `URLRequest` through both
    /// (Reader + Publisher monad stack).
    func flatMap<B>(_ f: @escaping (A) -> RequestPublisher<B>) -> RequestPublisher<B> {
        RequestPublisher<B> { request in
            self.run(request)
                .flatMap { a in f(a).run(request) }
                .eraseToAnyPublisher()
        }
    }

    /// Curried bind for point-free composition.
    static func bind<B>(_ f: @escaping (A) -> RequestPublisher<B>) -> (RequestPublisher<A>) -> RequestPublisher<B> {
        { $0.flatMap(f) }
    }

    /// Collapses a nested `RequestPublisher` by threading the same `URLRequest` into both layers.
    static func join<B>(_ nested: RequestPublisher<RequestPublisher<B>>) -> RequestPublisher<B>
    where A == RequestPublisher<B> {
        RequestPublisher<B> { request in
            nested.run(request)
                .flatMap { inner in inner.run(request) }
                .eraseToAnyPublisher()
        }
    }

    /// Kleisli composition (left-to-right): `(X -> m A) >=> (A -> m B) = X -> m B`.
    static func kleisli<X, B>(
        _ f: @escaping (X) -> RequestPublisher<A>,
        _ g: @escaping (A) -> RequestPublisher<B>
    ) -> (X) -> RequestPublisher<B> {
        { x in f(x).flatMap(g) }
    }

    /// Kleisli composition (right-to-left).
    static func kleisliBack<X, B>(
        _ g: @escaping (A) -> RequestPublisher<B>,
        _ f: @escaping (X) -> RequestPublisher<A>
    ) -> (X) -> RequestPublisher<B> {
        RequestPublisher.kleisli(f, g)
    }

    /// Recovers from failure by running an alternative `RequestPublisher`
    /// against the same `URLRequest`.
    func flatMapError(_ f: @escaping (HTTPError) -> RequestPublisher<A>) -> RequestPublisher<A> {
        RequestPublisher { request in
            self.run(request)
                .catch { error in f(error).run(request) }
                .eraseToAnyPublisher()
        }
    }
}
