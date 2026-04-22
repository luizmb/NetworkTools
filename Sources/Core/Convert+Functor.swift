import Foundation

// MARK: - Functor

public extension Convert {
    /// Transforms the output value; the input is threaded through unchanged.
    func map<B>(_ f: @escaping (Output) -> B) -> Convert<Input, B, Failure> {
        Convert<Input, B, Failure> { input in run(input).map(f) }
    }

    /// Curried fmap for point-free composition.
    static func fmap<B>(_ f: @escaping (Output) -> B) -> (Convert<Input, Output, Failure>) -> Convert<Input, B, Failure> {
        { $0.map(f) }
    }

    /// Replaces the output value with a constant.
    func replace<B>(with value: B) -> Convert<Input, B, Failure> {
        map { _ in value }
    }

    /// Maps the failure side of the underlying result.
    func mapError<FailureB: Error>(_ f: @escaping (Failure) -> FailureB) -> Convert<Input, Output, FailureB> {
        .init { input in run(input).mapError(f) }
    }
}
