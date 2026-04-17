import Combine
import FP
import Foundation

// MARK: - RequestPublisher Functor Operators

// (<$>) :: (a -> b) -> RequestPublisher<a> -> RequestPublisher<b>
public func <£> <A, B>(_ f: @escaping (A) -> B, _ r: RequestPublisher<A>) -> RequestPublisher<B> {
    r.map(f)
}

// (<&>) :: RequestPublisher<a> -> (a -> b) -> RequestPublisher<b>
public func <&> <A, B>(_ r: RequestPublisher<A>, _ f: @escaping (A) -> B) -> RequestPublisher<B> {
    r.map(f)
}

// ($>) :: RequestPublisher<a> -> b -> RequestPublisher<b>
public func £> <A, B>(_ r: RequestPublisher<A>, _ value: B) -> RequestPublisher<B> {
    r.replace(with: value)
}

// (<$) :: b -> RequestPublisher<a> -> RequestPublisher<b>
public func <£ <A, B>(_ value: B, _ r: RequestPublisher<A>) -> RequestPublisher<B> {
    r £> value
}
