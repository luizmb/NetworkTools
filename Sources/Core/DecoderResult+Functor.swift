import Foundation

// MARK: - Functor

public extension DecoderResult {
    /// Transforms the decoded value; the same `Data` is threaded through unchanged.
    func map<B>(_ f: @escaping (D) -> B) -> DecoderResult<B> {
        DecoderResult<B> { data in run(data).map(f) }
    }

    /// Curried fmap for point-free composition.
    static func fmap<B>(_ f: @escaping (D) -> B) -> (DecoderResult<D>) -> DecoderResult<B> {
        { $0.map(f) }
    }

    /// Replaces the decoded value with a constant.
    func replace<B>(with value: B) -> DecoderResult<B> {
        map { _ in value }
    }

    /// Maps the failure side of the underlying result.
    func mapError(_ f: @escaping (DecodingError) -> DecodingError) -> DecoderResult<D> {
        DecoderResult { data in run(data).mapError(f) }
    }
}
