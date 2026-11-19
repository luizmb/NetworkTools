// SPDX-License-Identifier: Apache-2.0

/// The protocol-agnostic ways a byte-level parse can fail.
///
/// Every case carries the absolute `offset` in the original input where the problem was
/// detected, so protocol layers can produce precise diagnostics. A protocol with its own error
/// type embeds these with a `Prism<ProtocolError, BinaryParseError>` (see
/// the parser's `embed(_:)`).
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
