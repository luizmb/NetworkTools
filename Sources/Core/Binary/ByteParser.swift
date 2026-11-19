// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP

/// The input a ``ByteParser`` consumes: a slice of bytes whose `startIndex` is the absolute
/// offset of the next unread byte in the original buffer (handy for error reporting).
public typealias ByteInput = ArraySlice<UInt8>

/// A binary parser: a stateful computation over ``ByteInput`` that either produces an `A` or
/// fails with a typed `Failure`.
///
/// It is FP's `StatefulTResult` stack — `(inout ByteInput) -> Result<A, Failure>` — so it is
/// already a lawful Functor / Applicative / Monad, with every FP operator (`<£>`, `<*>`, `*>`,
/// `<*`, `>>-`, `>=>`) available. Core only adds the byte-level primitives and combinators that
/// a parser monad needs on top: reading integers, isolating a length-delimited region,
/// repetition and backtracking choice.
///
/// ```swift
/// typealias P<A> = ByteParser<A, BinaryParseError>
///
/// // A big-endian length-prefixed UTF-8 string, tacitly:
/// let string: P<String> = P<UInt16>.uint16(.big) >>- { P<String>.utf8(count: Int($0)) }
///
/// string.parseAll([0x00, 0x02, 0x68, 0x69])   // .success("hi")
/// ```
public typealias ByteParser<A, Failure: Error> = StatefulTResult<ByteInput, Failure, A>

/// Byte order of a fixed-width integer on the wire.
public enum Endianness: Sendable, Equatable {
    /// Most significant byte first ("network byte order").
    case big
    /// Least significant byte first.
    case little
}

// MARK: - Primitives

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A: Sendable {
    /// Fails without consuming input.
    /// - Parameter error: The failure to produce.
    /// - Returns: A parser that always fails with `error`.
    static func fail(_ error: E) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { _ in .failure(error) })
    }

    /// Lifts a `Result` into a parser that consumes nothing.
    /// - Parameter result: The value or failure to produce.
    /// - Returns: A parser yielding `result`.
    static func from(_ result: Result<A, E>) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { _ in result })
    }

    /// Runs `self`; if it fails, rewinds the input and runs `other` instead (backtracking choice).
    /// - Parameter other: The fallback parser.
    /// - Returns: The first parser that succeeds.
    func orElse(_ other: ByteParser<A, E>) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { input in
            let saved = input
            switch rawValue.run(&input) {
            case let .success(value):
                return .success(value)
            case .failure:
                input = saved
                return other.rawValue.run(&input)
            }
        })
    }

    /// Validates the parsed value, failing with `error` when the predicate does not hold.
    /// - Parameters:
    ///   - predicate: The condition the value must satisfy.
    ///   - error: Builds the failure from the rejected value.
    /// - Returns: A parser that only succeeds for accepted values.
    func ensure(
        _ predicate: @escaping @Sendable (A) -> Bool,
        else error: @escaping @Sendable (A) -> E
    ) -> ByteParser<A, E> {
        flatMap { value in predicate(value) ? .pure(value) : .fail(error(value)) }
    }

    /// Parses the value and then refines it with a fallible conversion.
    /// - Parameter transform: The conversion, which may reject the value.
    /// - Returns: A parser of the converted value.
    func refine<B: Sendable>(_ transform: @escaping @Sendable (A) -> Result<B, E>) -> ByteParser<B, E> {
        flatMap(transform >>> ByteParser<B, E>.from)
    }

    /// Runs the parser against `input`, returning the value and the unconsumed remainder.
    /// - Parameter input: The bytes to parse.
    /// - Returns: The value with the remaining input, or the first failure.
    func parse(_ input: ByteInput) -> Result<(value: A, rest: ByteInput), E> {
        let (result, rest) = rawValue.runStateful(input)
        return result.map { (value: $0, rest: rest) }
    }

    /// Runs the parser against `input` and requires every byte to be consumed.
    /// - Parameter input: The bytes to parse.
    /// - Returns: The value, or a failure (including ``BinaryParseError/trailingBytes(count:offset:)``).
    func parseAll(_ input: ByteInput) -> Result<A, E> {
        (self <* ByteParser<Void, E>.end).parse(input).map(\.value)
    }

    /// Runs the parser against a whole byte array and requires every byte to be consumed.
    /// - Parameter bytes: The bytes to parse.
    /// - Returns: The value, or a failure.
    func parseAll(_ bytes: [UInt8]) -> Result<A, E> {
        parseAll(bytes[...])
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == UInt8 {
    /// Reads one byte.
    static var byte: ByteParser<UInt8, E> {
        ByteParser<UInt8, E>(Stateful { input in
            input.popFirst().map(Result.success) ?? .failure(.binary(.unexpectedEnd(needed: 1, offset: input.startIndex)))
        })
    }

    /// Looks at the next byte without consuming it.
    static var peek: ByteParser<UInt8, E> {
        ByteParser<UInt8, E>(Stateful { input in
            input.first.map(Result.success) ?? .failure(.binary(.unexpectedEnd(needed: 1, offset: input.startIndex)))
        })
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == [UInt8] {
    /// Reads exactly `count` bytes.
    /// - Parameter count: How many bytes to read.
    /// - Returns: A parser of the bytes read.
    static func bytes(count: Int) -> ByteParser<[UInt8], E> {
        ByteParser<[UInt8], E>(Stateful { input in
            guard count >= 0, input.count >= count else {
                return .failure(.binary(.unexpectedEnd(needed: count, offset: input.startIndex)))
            }
            let taken = Array(input.prefix(count))
            input = input.dropFirst(count)
            return .success(taken)
        })
    }

    /// Reads every remaining byte (always succeeds, possibly with an empty array).
    static var rest: ByteParser<[UInt8], E> {
        ByteParser<[UInt8], E>(Stateful { input in
            let all = Array(input)
            input = input.suffix(0)
            return .success(all)
        })
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == Void {
    /// Succeeds only when the input is exhausted.
    static var end: ByteParser<Void, E> {
        ByteParser<Void, E>(Stateful { input in
            input.isEmpty ? .success(()) : .failure(.binary(.trailingBytes(count: input.count, offset: input.startIndex)))
        })
    }

    /// Skips exactly `count` bytes.
    /// - Parameter count: How many bytes to skip.
    /// - Returns: A parser that discards `count` bytes.
    static func skip(_ count: Int) -> ByteParser<Void, E> {
        ByteParser<[UInt8], E>.bytes(count: count).map(ignore)
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == Bool {
    /// `true` when there is no more input. Consumes nothing.
    static var isAtEnd: ByteParser<Bool, E> {
        ByteParser<Bool, E>(Stateful { input in .success(input.isEmpty) })
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == Int {
    /// The absolute offset of the next unread byte. Consumes nothing.
    static var offset: ByteParser<Int, E> {
        ByteParser<Int, E>(Stateful { input in .success(input.startIndex) })
    }

    /// The number of unread bytes. Consumes nothing.
    static var remaining: ByteParser<Int, E> {
        ByteParser<Int, E>(Stateful { input in .success(input.count) })
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A: FixedWidthInteger & UnsignedInteger & Sendable {
    /// Reads a fixed-width unsigned integer in the given byte order.
    /// - Parameter endianness: The byte order on the wire.
    /// - Returns: A parser of the integer.
    static func integer(_ endianness: Endianness) -> ByteParser<A, E> {
        ByteParser<[UInt8], E>.bytes(count: MemoryLayout<A>.size)
            .map { bytes in
                (endianness == .big ? bytes : bytes.reversed()).reduce(A.zero) { ($0 << 8) | A($1) }
            }
    }

    /// Reads an unsigned LEB128-style variable-length integer: 7 bits per byte, least significant
    /// group first, high bit set on every byte but the last (MQTT's "Variable Byte Integer",
    /// protobuf varints, …).
    /// - Parameter maxBytes: The most bytes the encoding may use before it is rejected as malformed.
    /// - Returns: A parser of the integer.
    static func variableLength(maxBytes: Int) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { input in
            let start = input.startIndex
            let groups = input.prefix(maxBytes)
            guard let last = groups.firstIndex(where: { $0 & 0x80 == 0 }) else {
                return .failure(.binary(
                    groups.count < maxBytes
                        ? .unexpectedEnd(needed: groups.count + 1, offset: start)
                        : .malformedVariableLength(offset: start)
                ))
            }
            let encoded = groups[start...last]
            let value = encoded.reversed().reduce(UInt64.zero) { ($0 << 7) | UInt64($1 & 0x7F) }
            guard let fitting = A(exactly: value) else {
                return .failure(.binary(.malformedVariableLength(offset: start)))
            }
            input = input[(last + 1)...]
            return .success(fitting)
        })
    }
}

public extension StatefulTResult where S == ByteInput, E: ByteParseFailure, A == String {
    /// Reads `count` bytes and decodes them as UTF-8, rejecting invalid sequences.
    /// - Parameter count: The number of bytes the string occupies.
    /// - Returns: A parser of the string.
    static func utf8(count: Int) -> ByteParser<String, E> {
        ByteParser<Int, E>.offset.flatMap { offset in
            ByteParser<[UInt8], E>.bytes(count: count).refine { bytes in
                String(bytes: bytes, encoding: .utf8).map(Result.success)
                    ?? .failure(.binary(.invalidUTF8(offset: offset)))
            }
        }
    }
}

// MARK: - Combinators

/// Byte-level parser combinators that are not tied to a single result type.
public enum ByteParsers {
    /// Runs `parser` on exactly the next `count` bytes, as if they were the whole input.
    ///
    /// The parser must consume the whole region; leftover bytes fail with
    /// ``BinaryParseError/trailingBytes(count:offset:)``. This is how length-delimited regions
    /// (an MQTT packet body, a properties block, a TLV value) are parsed safely.
    /// - Parameters:
    ///   - count: The size of the region.
    ///   - parser: The parser for the region.
    /// - Returns: A parser that consumes exactly `count` bytes.
    public static func isolate<A: Sendable, E: ByteParseFailure>(
        _ count: Int,
        _ parser: ByteParser<A, E>
    ) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { input in
            guard count >= 0, input.count >= count else {
                return .failure(.binary(.unexpectedEnd(needed: count, offset: input.startIndex)))
            }
            let region = input.prefix(count)
            input = input.dropFirst(count)
            return parser.parseAll(region)
        })
    }

    /// Runs `parser` repeatedly until the input is exhausted.
    ///
    /// Meant for an ``isolate(_:_:)``-d region whose content is a list (e.g. a list of
    /// subscriptions). A parser that succeeds without consuming input fails the loop rather
    /// than spinning forever.
    /// - Parameter parser: The element parser.
    /// - Returns: A parser of every element, in order.
    public static func manyUntilEnd<A: Sendable, E: ByteParseFailure>(
        _ parser: ByteParser<A, E>
    ) -> ByteParser<[A], E> {
        ByteParser<[A], E>(Stateful { input in
            var values: [A] = []
            while !input.isEmpty {
                let before = input.startIndex
                switch parser.rawValue.run(&input) {
                case let .success(value) where input.startIndex > before:
                    values.append(value)
                case .success:
                    return .failure(.binary(.noProgress(offset: before)))
                case let .failure(error):
                    return .failure(error)
                }
            }
            return .success(values)
        })
    }

    /// Runs `parser` exactly `count` times.
    /// - Parameters:
    ///   - count: How many elements to parse.
    ///   - parser: The element parser.
    /// - Returns: A parser of `count` elements.
    public static func count<A: Sendable, E: ByteParseFailure>(
        _ count: Int,
        _ parser: ByteParser<A, E>
    ) -> ByteParser<[A], E> {
        (0..<max(count, 0)).reduce(ByteParser<[A], E>.pure([])) { acc, _ in
            ByteParser<[A], E>.liftA2 { values, value in values + [value] }(acc, parser)
        }
    }

    /// Optionally runs `parser`, backtracking to `nil` if it fails.
    /// - Parameter parser: The parser to try.
    /// - Returns: The value, or `nil` (input untouched) when it fails.
    public static func optional<A: Sendable, E: ByteParseFailure>(
        _ parser: ByteParser<A, E>
    ) -> ByteParser<A?, E> {
        parser.map(Optional.some).orElse(.pure(nil))
    }

    /// Runs `parser` only when `condition` holds, otherwise yields `nil` without consuming input.
    /// - Parameters:
    ///   - condition: Whether the field is present (typically a flag bit read earlier).
    ///   - parser: The field parser.
    /// - Returns: The value when present.
    public static func when<A: Sendable, E: ByteParseFailure>(
        _ condition: Bool,
        _ parser: ByteParser<A, E>
    ) -> ByteParser<A?, E> {
        condition ? parser.map(Optional.some) : .pure(nil)
    }
}

// MARK: - Alternative operator

/// Backtracking choice: runs `lhs`, and on failure rewinds and runs `rhs`.
/// (<|>) :: Parser a -> Parser a -> Parser a
public func <|> <A: Sendable, E: ByteParseFailure>(
    _ lhs: ByteParser<A, E>,
    _ rhs: ByteParser<A, E>
) -> ByteParser<A, E> {
    lhs.orElse(rhs)
}
