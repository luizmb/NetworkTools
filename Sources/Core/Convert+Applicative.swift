import Foundation

// MARK: - Applicative

public extension Convert {
    /// Lifts a pure value into `Convert`, ignoring the input.
    static func pure(_ value: Output) -> Convert<Input, Output, Failure> {
        Convert { _ in .success(value) }
    }

    /// Applies an input-dependent function to an input-dependent value.
    /// Both are run against the same input.
    static func apply<B>(_ f: Convert<Input, (Output) -> B, Failure>, _ r: Convert<Input, Output, Failure>) -> Convert<Input, B, Failure> {
        Convert<Input, B, Failure> { input in
            f.run(input).flatMap { fn in r.run(input).map(fn) }
        }
    }

    /// Sequences two conversions against the same input, discarding the left result.
    func seqRight<B>(_ rhs: Convert<Input, B, Failure>) -> Convert<Input, B, Failure> {
        Convert<Input, B, Failure> { input in run(input).flatMap { _ in rhs.run(input) } }
    }

    /// Sequences two conversions against the same input, discarding the right result.
    func seqLeft<B>(_ rhs: Convert<Input, B, Failure>) -> Convert<Input, Output, Failure> {
        Convert<Input, Output, Failure> { input in run(input).flatMap { value in rhs.run(input).map { _ in value } } }
    }
}
