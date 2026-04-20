import Foundation
import FP

/// A `FunctionWrapper` around `(Data) -> Result<D, DecodingError>`.
///
/// Represents a reusable decoding function as a first-class value,
/// supporting the full Functor / Applicative / Monad hierarchy.
public struct DecoderResult<D>: FunctionWrapper {
    public let run: (Data) -> Result<D, DecodingError>

    public init(_ fn: @escaping (Data) -> Result<D, DecodingError>) {
        run = fn
    }

    public func callAsFunction(_ data: Data) -> Result<D, DecodingError> {
        run(data)
    }
}
