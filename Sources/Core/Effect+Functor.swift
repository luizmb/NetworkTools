import FP

// MARK: - Functor

public extension Effect {
    /// Transforms the output value; input and environment thread through unchanged.
    func map<B: Sendable>(_ f: @escaping @Sendable (Output) -> B) -> Effect<Input, Environment, B, Failure> {
        .init { input in
            Reader { env in
                self.run(input).runReader(env).map { result in result.map(f) }
            }
        }
    }

    /// Curried fmap for point-free composition.
    static func fmap<B: Sendable>(
        _ f: @escaping @Sendable (Output) -> B
    ) -> (Effect) -> Effect<Input, Environment, B, Failure> {
        { $0.map(f) }
    }

    /// Replaces the output value with a constant.
    func replace<B: Sendable>(with value: B) -> Effect<Input, Environment, B, Failure> {
        map { _ in value }
    }

    /// Maps the failure side.
    func mapError<F2: Error>(_ f: @escaping @Sendable (Failure) -> F2) -> Effect<Input, Environment, Output, F2> {
        .init { input in
            Reader { env in
                self.run(input).runReader(env).map { result in result.mapError(f) }
            }
        }
    }
}
