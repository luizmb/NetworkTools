import Foundation
import FP

// MARK: - DecoderResult Functor Operators

// (<$>) :: (a -> b) -> DecoderResult<a> -> DecoderResult<b>
public func <£> <A, B>(_ f: @escaping (A) -> B, _ d: DecoderResult<A>) -> DecoderResult<B> {
    d.map(f)
}

// (<&>) :: DecoderResult<a> -> (a -> b) -> DecoderResult<b>
public func <&> <A, B>(_ d: DecoderResult<A>, _ f: @escaping (A) -> B) -> DecoderResult<B> {
    d.map(f)
}

// ($>) :: DecoderResult<a> -> b -> DecoderResult<b>
// swiftlint:disable:next identifier_name
public func £> <A, B>(_ d: DecoderResult<A>, _ value: B) -> DecoderResult<B> {
    d.replace(with: value)
}

// (<$) :: b -> DecoderResult<a> -> DecoderResult<b>
public func <£ <A, B>(_ value: B, _ d: DecoderResult<A>) -> DecoderResult<B> {
    d £> value
}
