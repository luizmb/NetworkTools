// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP

/// A binary encoder: a fallible conversion from `A` to bytes.
///
/// It is ``Convert`` specialised to `[UInt8]` output, so it inherits the Functor / Applicative /
/// Monad surface and `contramap`, and — because `[UInt8]` is a `Monoid` — encoders themselves
/// form a `Monoid` under `<>`: `lhs <> rhs` encodes the same input with both and concatenates
/// the bytes. A record encoder is the `<>` of its field encoders, each `contramap`-ped onto
/// the field it writes:
///
/// ```swift
/// typealias Enc<A> = ByteEncoder<A, BinaryEncodeError>
///
/// struct Point { let x: UInt16; let y: UInt16 }
///
/// let point: Enc<Point> =
///     Enc<UInt16>.integer(.big).contramap(\.x)
///     <> Enc<UInt16>.integer(.big).contramap(\.y)
///
/// point.run(Point(x: 1, y: 2))   // .success([0x00, 0x01, 0x00, 0x02])
/// ```
public typealias ByteEncoder<A, Failure: Error> = Convert<A, [UInt8], Failure>

// MARK: - Monoid

extension Convert: Semigroup where Output: Monoid {
    /// Runs both conversions on the same input and combines their outputs, left first.
    /// The first failure wins.
    /// - Parameters:
    ///   - lhs: The conversion whose output comes first.
    ///   - rhs: The conversion whose output comes second.
    /// - Returns: The combined conversion.
    public static func combine(_ lhs: Convert, _ rhs: Convert) -> Convert {
        Convert { input in
            lhs.run(input).flatMap { left in rhs.run(input).map { left <> $0 } }
        }
    }
}

extension Convert: Monoid where Output: Monoid {
    /// The conversion that ignores its input and outputs the empty value.
    public static var identity: Convert { .pure(.identity) }
}

// MARK: - Primitives

public extension Convert where Output == [UInt8], Failure: ByteEncodeFailure, Input == UInt8 {
    /// Writes a single byte.
    static var byte: ByteEncoder<UInt8, Failure> {
        Convert { .success([$0]) }
    }
}

public extension Convert where Output == [UInt8], Failure: ByteEncodeFailure, Input == [UInt8] {
    /// Writes the bytes as they are.
    static var raw: ByteEncoder<[UInt8], Failure> {
        Convert(Result.success)
    }
}

public extension Convert where Output == [UInt8], Failure: ByteEncodeFailure, Input == String {
    /// Writes the string's UTF-8 bytes (no length, no terminator).
    static var utf8: ByteEncoder<String, Failure> {
        Convert { .success(Array($0.utf8)) }
    }
}

public extension Convert where Output == [UInt8], Failure: ByteEncodeFailure, Input: FixedWidthInteger & UnsignedInteger {
    /// Writes a fixed-width unsigned integer in the given byte order.
    /// - Parameter endianness: The byte order on the wire.
    /// - Returns: An encoder of the integer.
    static func integer(_ endianness: Endianness) -> ByteEncoder<Input, Failure> {
        Convert { value in
            let bigEndian = (0..<MemoryLayout<Input>.size).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
            return .success(endianness == .big ? bigEndian : bigEndian.reversed())
        }
    }

    /// Writes an unsigned LEB128-style variable-length integer (7 bits per byte, least
    /// significant group first, continuation bit on every byte but the last).
    /// - Parameter maxBytes: The most bytes the encoding may use; larger values fail with
    ///   ``BinaryEncodeError/valueTooLarge(value:maxBytes:)``.
    /// - Returns: An encoder of the integer.
    static func variableLength(maxBytes: Int) -> ByteEncoder<Input, Failure> {
        Convert { value in
            let wide = UInt64(value)
            let groups = Swift.sequence(first: wide) { $0 >> 7 }
                .prefix { $0 > 0 }
                .map { UInt8($0 & 0x7F) }
            let digits = groups.isEmpty ? [UInt8.zero] : groups
            guard digits.count <= maxBytes else {
                return .failure(.binary(.valueTooLarge(value: wide, maxBytes: maxBytes)))
            }
            return .success(digits.enumerated().map { index, digit in index < digits.count - 1 ? digit | 0x80 : digit })
        }
    }
}

// MARK: - Combinators

/// Byte-level encoder combinators.
public enum ByteEncoders {
    /// Writes fixed bytes, ignoring the input.
    /// - Parameter bytes: The bytes to write.
    /// - Returns: A constant encoder.
    public static func constant<A, E: ByteEncodeFailure>(_ bytes: [UInt8]) -> ByteEncoder<A, E> {
        .pure(bytes)
    }

    /// A length writer: encodes an `Int` count as the fixed-width unsigned integer `T`, failing with
    /// ``BinaryEncodeError/lengthTooLarge(count:max:)`` when it does not fit.
    /// - Parameters:
    ///   - type: The integer type of the length field.
    ///   - endianness: Its byte order.
    /// - Returns: An encoder of lengths.
    public static func length<T: FixedWidthInteger & UnsignedInteger, E: ByteEncodeFailure>(
        _ type: T.Type,
        _ endianness: Endianness
    ) -> ByteEncoder<Int, E> {
        ByteEncoder<Int, E> { count in
            (T(exactly: count).map(Result.success) ?? .failure(.binary(.lengthTooLarge(count: count, max: UInt64(T.max)))))
                .flatMap(ByteEncoder<T, E>.integer(endianness).run)
        }
    }

    /// Writes `body`, preceded by its byte length written with `length`.
    /// - Parameters:
    ///   - length: The encoder of the length field (see ``length(_:_:)``).
    ///   - body: The encoder of the content.
    /// - Returns: A length-prefixed encoder.
    public static func prefixed<A, E: ByteEncodeFailure>(
        by length: ByteEncoder<Int, E>,
        _ body: ByteEncoder<A, E>
    ) -> ByteEncoder<A, E> {
        body.flatMap { bytes in length.contramap(const(bytes.count)).map { $0 + bytes } }
    }

    /// Writes nothing for `nil`, and `encoder` otherwise.
    /// - Parameter encoder: The encoder of the wrapped value.
    /// - Returns: An encoder of the optional.
    public static func optional<A, E: ByteEncodeFailure>(_ encoder: ByteEncoder<A, E>) -> ByteEncoder<A?, E> {
        Convert { value in value.map(encoder.run) ?? .success([]) }
    }

    /// Writes every element with `encoder`, concatenated in order.
    /// - Parameter encoder: The element encoder.
    /// - Returns: An encoder of the array.
    public static func many<A, E: ByteEncodeFailure>(_ encoder: ByteEncoder<A, E>) -> ByteEncoder<[A], E> {
        Convert { values in
            values.reduce(Result<[UInt8], E>.success([])) { acc, value in
                acc.flatMap { bytes in encoder.run(value).map { bytes + $0 } }
            }
        }
    }
}

// MARK: - Errors

/// The protocol-agnostic ways a byte-level encode can fail.
public enum BinaryEncodeError: Error, Equatable, Sendable {
    /// A variable-length integer needs more than `maxBytes` bytes.
    case valueTooLarge(value: UInt64, maxBytes: Int)
    /// A length-prefixed region holds `count` bytes but the length field can only express `max`.
    case lengthTooLarge(count: Int, max: UInt64)
}

/// A protocol-specific failure type that can embed a ``BinaryEncodeError``.
///
/// An enum case `case binary(BinaryEncodeError)` satisfies the requirement on its own.
public protocol ByteEncodeFailure: Error {
    /// Embeds a byte-level failure.
    /// - Parameter error: The underlying byte-level failure.
    /// - Returns: The protocol-specific failure.
    static func binary(_ error: BinaryEncodeError) -> Self
}

extension BinaryEncodeError: ByteEncodeFailure {
    /// A ``BinaryEncodeError`` embeds itself.
    /// - Parameter error: The byte-level failure.
    /// - Returns: `error` unchanged.
    public static func binary(_ error: BinaryEncodeError) -> BinaryEncodeError { error }
}
