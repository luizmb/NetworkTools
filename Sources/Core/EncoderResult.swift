import Foundation
import FP

/// A `FunctionWrapper` around `(E) -> Result<Data, EncodingError>`.
///
/// Represents a reusable encoding function as a first-class value.
/// Dual of `DecoderResult`: contravariant in `E` (maps over the *input* type).
public struct EncoderResult<E>: FunctionWrapper<E, Result<Data, EncodingError>> {
    public let run: (E) -> Result<Data, EncodingError>

    public init(_ fn: @escaping (E) -> Result<Data, EncodingError>) {
        run = fn
    }

    public func callAsFunction(_ value: E) -> Result<Data, EncodingError> {
        run(value)
    }
}
