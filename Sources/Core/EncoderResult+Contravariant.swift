import Foundation

// MARK: - Contravariant

public extension EncoderResult {
    /// Maps over the *input* type: adapt an `EncoderResult<E>` to accept `F`
    /// by pre-processing `F → E` before encoding.
    func contramap<F>(_ f: @escaping (F) -> E) -> EncoderResult<F> {
        EncoderResult<F> { run(f($0)) }
    }

    /// Maps the failure side of the underlying result.
    func mapError(_ f: @escaping (EncodingError) -> EncodingError) -> EncoderResult<E> {
        EncoderResult { run($0).mapError(f) }
    }
}
