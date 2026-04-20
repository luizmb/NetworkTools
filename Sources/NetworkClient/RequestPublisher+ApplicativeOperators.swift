#if canImport(Combine)
import Combine
import Foundation
import FP

// MARK: - RequestPublisher Applicative Operators

// (<*>) :: RequestPublisher<(a -> b)> -> RequestPublisher<a> -> RequestPublisher<b>
public func <*> <A, B>(_ f: RequestPublisher<(A) -> B>, _ r: RequestPublisher<A>) -> RequestPublisher<B> {
    RequestPublisher.apply(f, r)
}

// (*>) :: RequestPublisher<a> -> RequestPublisher<b> -> RequestPublisher<b>
public func *> <A, B>(_ lhs: RequestPublisher<A>, _ rhs: RequestPublisher<B>) -> RequestPublisher<B> {
    lhs.seqRight(rhs)
}

// (<*) :: RequestPublisher<a> -> RequestPublisher<b> -> RequestPublisher<a>
public func <* <A, B>(_ lhs: RequestPublisher<A>, _ rhs: RequestPublisher<B>) -> RequestPublisher<A> {
    lhs.seqLeft(rhs)
}
#endif
