import Foundation

// MARK: - Monad

public extension Convert {
    /// Chains two `Convert`s, threading the same input through both.
    func flatMap<B>(_ f: @escaping (Output) -> Convert<Input, B, Failure>) -> Convert<Input, B, Failure> {
        Convert<Input, B, Failure> { input in run(input).flatMap { d in f(d).run(input) } }
    }

    /// Curried bind for point-free composition.
    static func bind<B>(
        _ f: @escaping (Output) -> Convert<Input, B, Failure>
    ) -> (Convert<Input, Output, Failure>) -> Convert<Input, B, Failure> {
        { $0.flatMap(f) }
    }

    /// Kleisli composition (left-to-right): `(X -> m A) >=> (A -> m B) = X -> m B`.
    static func kleisli<X, B>(
        _ f: @escaping (X) -> Convert<Input, Output, Failure>,
        _ g: @escaping (Output) -> Convert<Input, B, Failure>
    ) -> (X) -> Convert<Input, B, Failure> {
        { x in f(x).flatMap(g) }
    }

    /// Kleisli composition (right-to-left).
    static func kleisliBack<X, B>(
        _ g: @escaping (Output) -> Convert<Input, B, Failure>,
        _ f: @escaping (X) -> Convert<Input, Output, Failure>
    ) -> (X) -> Convert<Input, B, Failure> {
        Convert.kleisli(f, g)
    }

    /// Recovers from failure by running an alternative `Convert` against the same input.
    func flatMapError<FailureB>(_ f: @escaping (Failure) -> Convert<Input, Output, FailureB>) -> Convert<Input, Output, FailureB> {
        .init { input in
            switch run(input) {
            case .success(let v): .success(v)
            case .failure(let e): f(e).run(input)
            }
        }
    }
}
