import Foundation

// MARK: - Applicative

public extension DecoderResult {
    /// Lifts a pure value into `DecoderResult`, ignoring the `Data`.
    static func pure(_ value: D) -> DecoderResult<D> {
        DecoderResult { _ in .success(value) }
    }

    /// Applies a data-dependent function to a data-dependent value.
    /// Both are run against the same `Data`.
    static func apply<B>(_ f: DecoderResult<(D) -> B>, _ r: DecoderResult<D>) -> DecoderResult<B> {
        DecoderResult<B> { data in
            f.run(data).flatMap { fn in r.run(data).map(fn) }
        }
    }

    /// Sequences two decoders against the same data, discarding the left result.
    func seqRight<B>(_ rhs: DecoderResult<B>) -> DecoderResult<B> {
        DecoderResult<B> { data in run(data).flatMap { _ in rhs.run(data) } }
    }

    /// Sequences two decoders against the same data, discarding the right result.
    func seqLeft<B>(_ rhs: DecoderResult<B>) -> DecoderResult<D> {
        DecoderResult<D> { data in run(data).flatMap { value in rhs.run(data).map { _ in value } } }
    }
}
