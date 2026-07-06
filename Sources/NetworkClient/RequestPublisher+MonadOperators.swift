// SPDX-License-Identifier: Apache-2.0

#if canImport(Combine)
import Combine
import Foundation
import FP

// MARK: - RequestPublisher Monad Operators

// (>>-) :: RequestPublisher<a> -> (a -> RequestPublisher<b>) -> RequestPublisher<b>
public func >>- <A, B>(_ r: RequestPublisher<A>, _ f: @escaping @Sendable (A) -> RequestPublisher<B>) -> RequestPublisher<B> {
    r.flatMap(f)
}

// (-<<) :: (a -> RequestPublisher<b>) -> RequestPublisher<a> -> RequestPublisher<b>
public func -<< <A, B>(_ f: @escaping @Sendable (A) -> RequestPublisher<B>, _ r: RequestPublisher<A>) -> RequestPublisher<B> {
    r.flatMap(f)
}

// (>=>) :: (x -> RequestPublisher<a>) -> (a -> RequestPublisher<b>) -> x -> RequestPublisher<b>
public func >=> <X, A, B>(
    _ f: @escaping @Sendable (X) -> RequestPublisher<A>,
    _ g: @escaping @Sendable (A) -> RequestPublisher<B>
) -> @Sendable (X) -> RequestPublisher<B> {
    RequestPublisher.kleisli(f, g)
}

// (<=<) :: (a -> RequestPublisher<b>) -> (x -> RequestPublisher<a>) -> x -> RequestPublisher<b>
public func <=< <X, A, B>(
    _ g: @escaping @Sendable (A) -> RequestPublisher<B>,
    _ f: @escaping @Sendable (X) -> RequestPublisher<A>
) -> @Sendable (X) -> RequestPublisher<B> {
    RequestPublisher.kleisliBack(g, f)
}
#endif
