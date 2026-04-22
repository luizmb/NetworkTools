import FP

// MARK: - Monad

public extension Effect {
    /// Chains two effects, threading the same input and environment through both.
    func flatMap<B: Sendable>(
        _ f: @escaping @Sendable (Output) -> Effect<Input, Environment, B, Failure>
    ) -> Effect<Input, Environment, B, Failure> where Input: Sendable, Environment: Sendable {
        .init { (input: Input) in
            Reader { (env: Environment) in
                self.run(input).runReader(env).flatMap { (result: Result<Output, Failure>) in
                    switch result {
                    case .failure(let e): DeferredTask { .failure(e) }
                    case .success(let a): f(a).run(input).runReader(env)
                    }
                }
            }
        }
    }

    /// Curried bind for point-free composition.
    static func bind<B: Sendable>(
        _ f: @escaping @Sendable (Output) -> Effect<Input, Environment, B, Failure>
    ) -> (Effect) -> Effect<Input, Environment, B, Failure> where Input: Sendable, Environment: Sendable {
        { $0.flatMap(f) }
    }

    /// Kleisli composition (left-to-right): `(X -> m A) >=> (A -> m B) = X -> m B`.
    /// Input and environment stay fixed; only the output type varies.
    static func kleisli<X, B: Sendable>(
        _ f: @escaping (X) -> Effect<Input, Environment, Output, Failure>,
        _ g: @escaping @Sendable (Output) -> Effect<Input, Environment, B, Failure>
    ) -> (X) -> Effect<Input, Environment, B, Failure> where Input: Sendable, Environment: Sendable {
        { x in f(x).flatMap(g) }
    }

    /// Kleisli composition (right-to-left).
    static func kleisliBack<X, B: Sendable>(
        _ g: @escaping @Sendable (Output) -> Effect<Input, Environment, B, Failure>,
        _ f: @escaping (X) -> Effect<Input, Environment, Output, Failure>
    ) -> (X) -> Effect<Input, Environment, B, Failure> where Input: Sendable, Environment: Sendable {
        Effect.kleisli(f, g)
    }

    /// Recovers from failure by running an alternative effect against the same input.
    func flatMapError<F2: Error>(
        _ f: @escaping @Sendable (Failure) -> Effect<Input, Environment, Output, F2>
    ) -> Effect<Input, Environment, Output, F2> where Input: Sendable, Environment: Sendable {
        .init { (input: Input) in
            Reader { (env: Environment) in
                self.run(input).runReader(env).flatMap { (result: Result<Output, Failure>) in
                    switch result {
                    case .success(let a): DeferredTask { .success(a) }
                    case .failure(let e): f(e).run(input).runReader(env)
                    }
                }
            }
        }
    }
}
