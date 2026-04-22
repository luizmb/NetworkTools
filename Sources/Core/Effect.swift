import FP

/// A composable, typed effect: `Input -> Reader<Environment, DeferredTask<Result<Output, Failure>>>`.
///
/// Supports the full Functor / Applicative / Monad hierarchy over the `Output` dimension,
/// and `contramap` over both `Input` and `Environment`.
///
/// Chaining methods (`flatMap`, `seqLeft`, `seqRight`, `apply`, `flatMapError`) require
/// `Input: Sendable` and `Environment: Sendable` because they capture those values inside
/// `DeferredTask`'s `@Sendable` closures.
public struct Effect<Input, Environment, Output: Sendable, Failure: Error>: @unchecked Sendable {
    public let run: (Input) -> Reader<Environment, DeferredTask<Result<Output, Failure>>>

    public init(_ run: @escaping (Input) -> Reader<Environment, DeferredTask<Result<Output, Failure>>>) {
        self.run = run
    }
}
