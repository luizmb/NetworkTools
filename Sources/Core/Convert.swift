import Foundation
import FP

/// A `FunctionWrapper` around `(Input) -> Result<Output, Failure>`.
///
/// Represents a reusable, composable fallible conversion as a first-class value,
/// supporting the full Functor / Applicative / Monad hierarchy.
///
/// Concrete typealiases pin the type parameters for common uses:
/// - `DataDecoder<O>` = `Convert<Data, O, DecodingError>`
/// - `DataEncoder<I>` = `Convert<I, Data, EncodingError>`
/// - `DictionaryDecoder<O>` = `Convert<[String: String], O, DecodingError>`
public struct Convert<Input, Output, Failure: Error>: FunctionWrapper, @unchecked Sendable {
    public let run: (Input) -> Result<Output, Failure>

    public init(_ fn: @escaping (Input) -> Result<Output, Failure>) {
        run = fn
    }

    public func callAsFunction(_ input: Input) -> Result<Output, Failure> {
        run(input)
    }
}
