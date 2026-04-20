import Foundation
import FP

// MARK: - DecoderResult Monad Operators

// (>>-) :: DecoderResult<a> -> (a -> DecoderResult<b>) -> DecoderResult<b>
public func >>- <A, B>(_ d: DecoderResult<A>, _ f: @escaping (A) -> DecoderResult<B>) -> DecoderResult<B> {
    d.flatMap(f)
}

// (-<<) :: (a -> DecoderResult<b>) -> DecoderResult<a> -> DecoderResult<b>
public func -<< <A, B>(_ f: @escaping (A) -> DecoderResult<B>, _ d: DecoderResult<A>) -> DecoderResult<B> {
    d.flatMap(f)
}

// (>=>) :: (x -> DecoderResult<a>) -> (a -> DecoderResult<b>) -> x -> DecoderResult<b>
public func >=> <X, A, B>(
    _ f: @escaping (X) -> DecoderResult<A>,
    _ g: @escaping (A) -> DecoderResult<B>
) -> (X) -> DecoderResult<B> {
    DecoderResult.kleisli(f, g)
}

// (<=<) :: (a -> DecoderResult<b>) -> (x -> DecoderResult<a>) -> x -> DecoderResult<b>
public func <=< <X, A, B>(
    _ g: @escaping (A) -> DecoderResult<B>,
    _ f: @escaping (X) -> DecoderResult<A>
) -> (X) -> DecoderResult<B> {
    DecoderResult.kleisliBack(g, f)
}
