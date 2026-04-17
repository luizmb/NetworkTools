import FP
import Foundation

// MARK: - DecoderResult Applicative Operators

// (<*>) :: DecoderResult<(a -> b)> -> DecoderResult<a> -> DecoderResult<b>
public func <*> <A, B>(_ f: DecoderResult<(A) -> B>, _ d: DecoderResult<A>) -> DecoderResult<B> {
    DecoderResult.apply(f, d)
}

// (*>) :: DecoderResult<a> -> DecoderResult<b> -> DecoderResult<b>
public func *> <A, B>(_ lhs: DecoderResult<A>, _ rhs: DecoderResult<B>) -> DecoderResult<B> {
    lhs.seqRight(rhs)
}

// (<*) :: DecoderResult<a> -> DecoderResult<b> -> DecoderResult<a>
public func <* <A, B>(_ lhs: DecoderResult<A>, _ rhs: DecoderResult<B>) -> DecoderResult<A> {
    lhs.seqLeft(rhs)
}
