import FP

// MARK: - Contravariant

public extension Effect {
    /// Maps over the *input* type: pre-processes `InputB → Input` before running.
    func contramap<InputB>(_ f: @escaping (InputB) -> Input) -> Effect<InputB, Environment, Output, Failure> {
        .init { self.run(f($0)) }
    }

    /// Maps over the *environment* type.
    func contramapEnvironment<EnvB>(_ f: @escaping (EnvB) -> Environment) -> Effect<Input, EnvB, Output, Failure> {
        .init { input in self.run(input).contramapEnvironment(f) }
    }
}
