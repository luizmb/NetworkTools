import Foundation

// MARK: - Contravariant

public extension Convert {
    /// Maps over the *input* type: adapts a `Convert<Input, Output, Failure>` to accept `InputB`
    /// by pre-processing `InputB → Input` before the conversion.
    func contramap<InputB>(_ f: @escaping (InputB) -> Input) -> Convert<InputB, Output, Failure> {
        .init { run(f($0)) }
    }
}
