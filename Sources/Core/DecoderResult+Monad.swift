import Foundation

// MARK: - Monad

public extension DecoderResult {

    /// Chains two `DecoderResult`s, threading the same `Data` through both.
    func flatMap<B>(_ f: @escaping (D) -> DecoderResult<B>) -> DecoderResult<B> {
        DecoderResult<B> { data in run(data).flatMap { d in f(d).run(data) } }
    }

    /// Curried bind for point-free composition.
    static func bind<B>(_ f: @escaping (D) -> DecoderResult<B>) -> (DecoderResult<D>) -> DecoderResult<B> {
        { $0.flatMap(f) }
    }

    /// Kleisli composition (left-to-right): `(X -> m D) >=> (D -> m B) = X -> m B`.
    static func kleisli<X, B>(
        _ f: @escaping (X) -> DecoderResult<D>,
        _ g: @escaping (D) -> DecoderResult<B>
    ) -> (X) -> DecoderResult<B> {
        { x in f(x).flatMap(g) }
    }

    /// Kleisli composition (right-to-left).
    static func kleisliBack<X, B>(
        _ g: @escaping (D) -> DecoderResult<B>,
        _ f: @escaping (X) -> DecoderResult<D>
    ) -> (X) -> DecoderResult<B> {
        DecoderResult.kleisli(f, g)
    }

    /// Recovers from failure by running an alternative `DecoderResult` against the same `Data`.
    func flatMapError(_ f: @escaping (DecodingError) -> DecoderResult<D>) -> DecoderResult<D> {
        DecoderResult { data in
            switch run(data) {
            case .success(let v): .success(v)
            case .failure(let e): f(e).run(data)
            }
        }
    }
}
