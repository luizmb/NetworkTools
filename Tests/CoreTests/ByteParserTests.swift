// SPDX-License-Identifier: Apache-2.0

import Core
import FP
import Testing

private typealias P<A: Sendable> = ByteParser<A, BinaryParseError>

@Suite struct ByteParserTests {
    @Test func byteConsumesOne() {
        let result = P<UInt8>.byte.parse([0x01, 0x02][...])
        #expect((try? result.get().value) == 0x01)
        #expect((try? result.get().rest).map(Array.init) == [0x02])
    }

    @Test func byteOnEmptyInputFails() {
        #expect(P<UInt8>.byte.parseAll([]) == .failure(.unexpectedEnd(needed: 1, offset: 0)))
    }

    @Test func bigEndianUInt16() {
        #expect(P<UInt16>.integer(.big).parseAll([0x12, 0x34]) == .success(0x1234))
    }

    @Test func littleEndianUInt32() {
        #expect(P<UInt32>.integer(.little).parseAll([0x78, 0x56, 0x34, 0x12]) == .success(0x1234_5678))
    }

    static let varints: [([UInt8], UInt32)] = [
        ([0x00], 0),
        ([0x7F], 127),
        ([0x80, 0x01], 128),
        ([0xFF, 0x7F], 16_383),
        ([0x80, 0x80, 0x01], 16_384),
        ([0xFF, 0xFF, 0xFF, 0x7F], 268_435_455),
    ]

    @Test(arguments: varints)
    func variableLength(bytes: [UInt8], expected: UInt32) {
        #expect(P<UInt32>.variableLength(maxBytes: 4).parseAll(bytes) == .success(expected))
    }

    @Test func variableLengthTooLong() {
        #expect(
            P<UInt32>.variableLength(maxBytes: 4).parseAll([0xFF, 0xFF, 0xFF, 0xFF, 0x01])
                == .failure(.malformedVariableLength(offset: 0))
        )
    }

    @Test func variableLengthIncomplete() {
        #expect(P<UInt32>.variableLength(maxBytes: 4).parseAll([0xFF]) == .failure(.unexpectedEnd(needed: 2, offset: 0)))
    }

    @Test func utf8() {
        #expect(P<String>.utf8(count: 2).parseAll([0x68, 0x69]) == .success("hi"))
    }

    @Test func invalidUTF8() {
        #expect(P<String>.utf8(count: 1).parseAll([0xFF]) == .failure(.invalidUTF8(offset: 0)))
    }

    @Test func monadicLengthPrefixedString() {
        let string = P<UInt16>.integer(.big) >>- { P<String>.utf8(count: Int($0)) }
        #expect(string.parseAll([0x00, 0x02, 0x68, 0x69]) == .success("hi"))
    }

    @Test func applicativeRecord() {
        struct Pair: Equatable { let a: UInt8; let b: UInt16 }
        let pair = P<Pair>.liftA2(Pair.init)(P<UInt8>.byte, P<UInt16>.integer(.big))
        #expect(pair.parseAll([0x01, 0x00, 0x02]) == .success(Pair(a: 1, b: 2)))
    }

    @Test func parseAllRejectsTrailingBytes() {
        #expect(P<UInt8>.byte.parseAll([0x01, 0x02]) == .failure(.trailingBytes(count: 1, offset: 1)))
    }

    @Test func isolateLimitsTheRegion() {
        let parser = ByteParsers.isolate(2, ByteParsers.manyUntilEnd(P<UInt8>.byte)) <* P<UInt8>.byte
        #expect(parser.parseAll([0x01, 0x02, 0x03]) == .success([0x01, 0x02]))
    }

    @Test func isolateRequiresFullConsumption() {
        #expect(ByteParsers.isolate(2, P<UInt8>.byte).parseAll([0x01, 0x02]) == .failure(.trailingBytes(count: 1, offset: 1)))
    }

    @Test func orElseBacktracks() {
        let twoBytes = P<UInt16>.integer(.big)
        let oneByte = P<UInt8>.byte.map(UInt16.init)
        #expect((twoBytes <|> oneByte).parseAll([0x05]) == .success(5))
    }

    @Test func countRepeats() {
        #expect(ByteParsers.count(3, P<UInt8>.byte).parseAll([1, 2, 3]) == .success([1, 2, 3]))
    }

    @Test func optionalYieldsNilWithoutConsuming() {
        let parser = ByteParsers.optional(P<UInt16>.integer(.big)) <* P<UInt8>.byte
        #expect(parser.parseAll([0x09]) == .success(nil))
    }

    @Test func manyUntilEndDetectsNoProgress() {
        #expect(ByteParsers.manyUntilEnd(P<Int>.offset).parseAll([0x01]) == .failure(.noProgress(offset: 0)))
    }

    @Test func ensureRejects() {
        let even = P<UInt8>.byte.ensure({ $0.isMultiple(of: 2) }, else: { _ in .noProgress(offset: 99) })
        #expect(even.parseAll([3]) == .failure(.noProgress(offset: 99)))
        #expect(even.parseAll([4]) == .success(4))
    }
}
