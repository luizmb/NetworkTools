import FP

// MARK: - Applicative

public extension Effect {
    /// Lifts a pure value into `Effect`, ignoring the input and environment.
    static func pure(_ value: Output) -> Effect {
        .init { _ in Reader { _ in DeferredTask { .success(value) } } }
    }

    /// Applies an input-dependent function effect to an input-dependent value effect.
    /// Both are run against the same input and environment; the function effect short-circuits on failure.
    static func apply<B: Sendable>(
        _ ff: Effect<Input, Environment, @Sendable (Output) -> B, Failure>,
        _ r: Effect<Input, Environment, Output, Failure>
    ) -> Effect<Input, Environment, B, Failure> where Input: Sendable, Environment: Sendable {
        .init { (input: Input) in
            Reader { (env: Environment) in
                ff.run(input).runReader(env).flatMap { (fResult: Result<@Sendable (Output) -> B, Failure>) in
                    switch fResult {
                    case .failure(let e): DeferredTask { .failure(e) }
                    case .success(let f): r.run(input).runReader(env).map { aResult in aResult.map(f) }
                    }
                }
            }
        }
    }

    /// Sequences two effects against the same input, discarding the left result.
    func seqRight<B: Sendable>(_ rhs: Effect<Input, Environment, B, Failure>) -> Effect<Input, Environment, B, Failure>
    where Input: Sendable, Environment: Sendable {
        .init { (input: Input) in
            Reader { (env: Environment) in
                self.run(input).runReader(env).flatMap { (result: Result<Output, Failure>) in
                    switch result {
                    case .failure(let e): DeferredTask { .failure(e) }
                    case .success: rhs.run(input).runReader(env)
                    }
                }
            }
        }
    }

    /// Sequences two effects against the same input, discarding the right result.
    func seqLeft<B: Sendable>(_ rhs: Effect<Input, Environment, B, Failure>) -> Effect<Input, Environment, Output, Failure>
    where Input: Sendable, Environment: Sendable {
        .init { (input: Input) in
            Reader { (env: Environment) in
                self.run(input).runReader(env).flatMap { (result: Result<Output, Failure>) in
                    switch result {
                    case .failure(let e): DeferredTask { .failure(e) }
                    case .success(let value):
                        rhs.run(input).runReader(env).map { innerResult in innerResult.map { _ in value } }
                    }
                }
            }
        }
    }
}
