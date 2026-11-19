// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import Testing

@Suite struct PacketStreamTests {
    private let empty = PacketStream(version: .v5, maximumPacketSize: 1 << 16)

    private func encoded(_ packets: [Packet]) -> [UInt8] {
        packets.flatMap { (try? $0.encode(for: .v5).get()) ?? [] }
    }

    @Test func wholePacketsInOneChunk() {
        let packets = Array(everyPacketV5.dropFirst())
        let (result, stream) = PacketStream.feed(encoded(packets)).runStateful(empty)
        #expect(result == .success(packets))
        #expect(stream.buffer.isEmpty)
    }

    @Test func byteByByte() {
        let packets = everyPacketV5
        let (received, stream) = encoded(packets).reduce(([Packet](), empty)) { acc, byte in
            let (result, next) = PacketStream.feed([byte]).runStateful(acc.1)
            return (acc.0 + ((try? result.get()) ?? []), next)
        }
        #expect(received == packets)
        #expect(stream.buffer.isEmpty)
    }

    @Test func keepsAPartialPacket() {
        let all = encoded([.pingReq, .pingResp])
        let (result, stream) = PacketStream.feed(Array(all.dropLast())).runStateful(empty)
        #expect(result == .success([.pingReq]))
        #expect(stream.buffer == [0xD0])
    }

    @Test func rejectsOversizedPacketsBeforeBuffering() {
        let small = PacketStream(version: .v5, maximumPacketSize: 10)
        let (result, _) = PacketStream.feed([0x30, 0xFF, 0x7F]).runStateful(small)
        #expect(result == .failure(.packetTooLarge(16_386, maximum: 10)))
    }

    @Test func reportsMalformedRemainingLength() {
        let (result, _) = PacketStream.feed([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]).runStateful(empty)
        #expect(result == .failure(.decoding(.binary(.malformedVariableLength(offset: 1)))))
    }

    @Test func reportsInvalidPackets() {
        let (result, _) = PacketStream.feed([0x00, 0x00]).runStateful(empty)
        #expect(result == .failure(.decoding(.reservedPacketType(0))))
    }
}
