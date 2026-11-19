// SPDX-License-Identifier: Apache-2.0

/// The protocol-agnostic ways a byte-level parse can fail.
///
/// Every case carries the absolute `offset` in the original input where the problem was
/// detected, so protocol layers can produce precise diagnostics.
public enum BinaryParseError: Error, Hashable, Sendable {
    /// The input ended while `needed` more bytes were required at `offset`.
    case unexpectedEnd(needed: Int, offset: Int)
    /// A parse that had to consume all input left `count` bytes unread at `offset`.
    case trailingBytes(count: Int, offset: Int)
    /// A variable-length integer used too many bytes or overflowed its type.
    case malformedVariableLength(offset: Int)
    /// A string region was not valid UTF-8.
    case invalidUTF8(offset: Int)
    /// A repetition's element parser succeeded without consuming any input.
    case noProgress(offset: Int)
}

/// A protocol-specific failure type that can embed a ``BinaryParseError``.
///
/// Byte primitives are generic over this protocol, so a protocol layer parses directly in its
/// own error type instead of mapping errors after every primitive. An enum case
/// `case binary(BinaryParseError)` satisfies the requirement on its own.
///
/// ```swift
/// enum MyDecodingError: ByteParseFailure {
///     case binary(BinaryParseError)
///     case unknownMessage(UInt8)
/// }
/// ```
public protocol ByteParseFailure: Error {
    /// Embeds a byte-level failure.
    /// - Parameter error: The underlying byte-level failure.
    /// - Returns: The protocol-specific failure.
    static func binary(_ error: BinaryParseError) -> Self
}

extension BinaryParseError: ByteParseFailure {
    /// A ``BinaryParseError`` embeds itself.
    /// - Parameter error: The byte-level failure.
    /// - Returns: `error` unchanged.
    public static func binary(_ error: BinaryParseError) -> BinaryParseError { error }
}
