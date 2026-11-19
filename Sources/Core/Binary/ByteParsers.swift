// SPDX-License-Identifier: Apache-2.0

import FP

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
    ///   - errors: Embeds this combinator's own byte-level failures into `E`.
    /// - Returns: A parser that consumes exactly `count` bytes.
    public static func isolate<A: Sendable, E: Error>(
        _ count: Int,
        _ parser: ByteParser<A, E>,
        errors: Prism<E, BinaryParseError>
    ) -> ByteParser<A, E> {
        ByteParser<A, E>(Stateful { input in
            guard count >= 0, input.count >= count else {
                return .failure(errors.review(.unexpectedEnd(needed: count, offset: input.startIndex)))
            }
            let region = input.prefix(count)
            input = input.dropFirst(count)
            return parser.parseAll(region, errors: errors)
        })
    }

    /// Runs `parser` repeatedly until the input is exhausted.
    ///
    /// Meant for an ``isolate(_:_:errors:)``-d region whose content is a list (e.g. a list of
    /// subscriptions). A parser that succeeds without consuming input fails the loop rather
    /// than spinning forever.
    /// - Parameters:
    ///   - parser: The element parser.
    ///   - errors: Embeds this combinator's own byte-level failure into `E`.
    /// - Returns: A parser of every element, in order.
    public static func manyUntilEnd<A: Sendable, E: Error>(
        _ parser: ByteParser<A, E>,
        errors: Prism<E, BinaryParseError>
    ) -> ByteParser<[A], E> {
        ByteParser<[A], E>(Stateful { input in
            var values: [A] = []
            while !input.isEmpty {
                let before = input.startIndex
                switch parser.rawValue.run(&input) {
                case let .success(value) where input.startIndex > before:
                    values.append(value)
                case .success:
                    return .failure(errors.review(.noProgress(offset: before)))
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
    public static func count<A: Sendable, E: Error>(
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
    public static func optional<A: Sendable, E: Error>(
        _ parser: ByteParser<A, E>
    ) -> ByteParser<A?, E> {
        parser.map(Optional.some).orElse(.pure(nil))
    }

    /// Runs `parser` only when `condition` holds, otherwise yields `nil` without consuming input.
    /// - Parameters:
    ///   - condition: Whether the field is present (typically a flag bit read earlier).
    ///   - parser: The field parser.
    /// - Returns: The value when present.
    public static func when<A: Sendable, E: Error>(
        _ condition: Bool,
        _ parser: ByteParser<A, E>
    ) -> ByteParser<A?, E> {
        condition ? parser.map(Optional.some) : .pure(nil)
    }
}

// MARK: - Alternative operator

/// Backtracking choice: runs `lhs`, and on failure rewinds and runs `rhs`.
/// (<|>) :: Parser a -> Parser a -> Parser a
public func <|> <A: Sendable, E: Error>(
    _ lhs: ByteParser<A, E>,
    _ rhs: ByteParser<A, E>
) -> ByteParser<A, E> {
    lhs.orElse(rhs)
}
