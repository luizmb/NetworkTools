// SPDX-License-Identifier: Apache-2.0

import Core
import FP
import Testing

private typealias Enc<A> = ByteEncoder<A, BinaryEncodeError>

@Suite struct ByteEncoderTests {
    @Test func bigEndian() {
        #expect(Enc<UInt16>.integer(.big).run(0x1234) == .success([0x12, 0x34]))
    }

    @Test func littleEndian() {
        #expect(Enc<UInt32>.integer(.little).run(0x1234_5678) == .success([0x78, 0x56, 0x34, 0x12]))
    }

    static let varints: [(UInt32, [UInt8])] = [
        (0, [0x00]),
        (127, [0x7F]),
        (128, [0x80, 0x01]),
        (16_383, [0xFF, 0x7F]),
        (268_435_455, [0xFF, 0xFF, 0xFF, 0x7F]),
    ]

    @Test(arguments: varints)
    func variableLength(value: UInt32, expected: [UInt8]) {
        #expect(Enc<UInt32>.variableLength(maxBytes: 4).run(value) == .success(expected))
    }

    @Test func variableLengthOverflow() {
        #expect(
            Enc<UInt32>.variableLength(maxBytes: 4).run(268_435_456)
                == .failure(.valueTooLarge(value: 268_435_456, maxBytes: 4))
        )
    }

    @Test func monoidConcatenatesFields() {
        struct Point { let x: UInt16; let y: UInt16 }
        let point = Enc<UInt16>.integer(.big).contramap(\Point.x) <> Enc<UInt16>.integer(.big).contramap(\Point.y)
        #expect(point.run(Point(x: 1, y: 2)) == .success([0x00, 0x01, 0x00, 0x02]))
    }

    @Test func monoidIdentity() {
        let byte = Enc<UInt8>.byte
        #expect((Enc<UInt8>.identity <> byte).run(7) == byte.run(7))
        #expect((byte <> .identity).run(7) == byte.run(7))
    }

    @Test func lengthPrefixed() {
        let string: Enc<String> = ByteEncoders.prefixed(by: ByteEncoders.length(UInt16.self, .big), .utf8)
        #expect(string.run("hi") == .success([0x00, 0x02, 0x68, 0x69]))
    }

    @Test func lengthPrefixOverflow() {
        let short: Enc<[UInt8]> = ByteEncoders.prefixed(by: ByteEncoders.length(UInt8.self, .big), .raw)
        #expect(short.run(Array(repeating: 0, count: 256)) == .failure(.lengthTooLarge(count: 256, max: 255)))
    }

    @Test func optionalAndMany() {
        #expect(ByteEncoders.optional(Enc<UInt8>.byte).run(nil) == .success([]))
        #expect(ByteEncoders.many(Enc<UInt8>.byte).run([1, 2]) == .success([1, 2]))
    }

    @Test func roundTripsThroughParser() {
        let encoded = (try? Enc<UInt32>.variableLength(maxBytes: 4).run(321_123).get()) ?? []
        #expect(ByteParser<UInt32, BinaryParseError>.variableLength(maxBytes: 4).parseAll(encoded) == .success(321_123))
    }
}
