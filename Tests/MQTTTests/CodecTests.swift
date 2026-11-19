// SPDX-License-Identifier: Apache-2.0

import MQTT
import Testing

@Suite struct CodecRoundTripTests {
    @Test(arguments: everyPacketV5)
    func roundTripsInV5(packet: Packet) {
        let decoded = packet.encode(for: .v5).mapError(CodecFailure.encoding)
            .flatMap { Packet.decode($0, for: .v5).mapError(CodecFailure.decoding) }
        #expect(decoded == .success(packet))
    }

    @Test(arguments: everyPacketV311)
    func roundTripsInV311(packet: Packet) {
        let decoded = packet.encode(for: .v3_1_1).mapError(CodecFailure.encoding)
            .flatMap { Packet.decode($0, for: .v3_1_1).mapError(CodecFailure.decoding) }
        #expect(decoded == .success(packet))
    }
}

enum CodecFailure: Error, Equatable {
    case encoding(MQTTEncodingError)
    case decoding(MQTTDecodingError)
}

@Suite struct CodecWireFormatTests {
    // Bytes observed from a Mosquitto 2.0.22 broker (Elegoo Centauri Carbon 2) on 2026-11-19.

    @Test func connAckNotAuthorizedV311() {
        #expect(
            Packet.decode(bytes("20 02 00 05"), for: .v3_1_1)
                == .success(.connAck(ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])))
        )
    }

    @Test func connAckNotAuthorizedV5() {
        #expect(
            Packet.decode(bytes("20 03 00 87 00"), for: .v5)
                == .success(.connAck(ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])))
        )
    }

    @Test func connAckAccepted() {
        #expect(
            Packet.decode(bytes("20 02 00 00"), for: .v3_1_1)
                == .success(.connAck(ConnAck(sessionPresent: false, reasonCode: .success, properties: [])))
        )
    }

    @Test func subAckGrantedQoS0Twice() {
        #expect(
            Packet.decode(bytes("90 04 00 01 00 00"), for: .v3_1_1)
                == .success(.subAck(SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS0, .grantedQoS0], properties: [])))
        )
    }

    @Test func connectV311MatchesTheProbe() {
        let connect = Connect(
            protocolVersion: .v3_1_1,
            clientIdentifier: "probe-nt",
            cleanStart: true,
            keepAlive: 30,
            will: nil,
            userName: "elegoo",
            password: Array("000000".utf8),
            properties: []
        )
        #expect(
            Packet.connect(connect).encode(for: .v3_1_1)
                == .success(bytes("102400044d51545404c2001e000870726f62652d6e740006656c65676f6f0006303030303030"))
        )
    }

    @Test func connectV5MatchesTheProbe() {
        let connect = Connect(
            protocolVersion: .v5,
            clientIdentifier: "probe-nt",
            cleanStart: true,
            keepAlive: 30,
            will: nil,
            userName: "elegoo",
            password: Array("000000".utf8),
            properties: []
        )
        #expect(
            Packet.connect(connect).encode(for: .v5)
                == .success(bytes("102500044d51545405c2001e00000870726f62652d6e740006656c65676f6f0006303030303030"))
        )
    }

    @Test func pingAndDisconnect() {
        #expect(Packet.pingReq.encode(for: .v3_1_1) == .success([0xC0, 0x00]))
        #expect(Packet.pingResp.encode(for: .v5) == .success([0xD0, 0x00]))
        #expect(Packet.disconnect(.normal).encode(for: .v5) == .success([0xE0, 0x00]))
    }

    @Test func shortestAcknowledgementForms() {
        #expect(Packet.pubAck(.success(id(1))).encode(for: .v5) == .success([0x40, 0x02, 0x00, 0x01]))
        #expect(
            Packet.pubAck(Acknowledgement(packetIdentifier: id(1), reasonCode: .noMatchingSubscribers, properties: []))
                .encode(for: .v5) == .success([0x40, 0x03, 0x00, 0x01, 0x10])
        )
        #expect(Packet.pubRel(.success(id(1))).encode(for: .v3_1_1) == .success([0x62, 0x02, 0x00, 0x01]))
    }

    @Test func publishQoS0FromThePrinter() {
        let json = "{\"type\":\"PONG\"}"
        let topicBytes = Array("elegoo/SERIAL/client/api_response".utf8)
        let body = [UInt8(0), UInt8(topicBytes.count)] + topicBytes + Array(json.utf8)
        let packet = [0x30, UInt8(body.count)] + body
        #expect(
            Packet.decode(packet, for: .v3_1_1) == .success(.publish(Publish(
                topic: topic("elegoo/SERIAL/client/api_response"),
                payload: Array(json.utf8),
                delivery: .atMostOnce,
                retain: false,
                duplicate: false,
                properties: []
            )))
        )
    }

    @Test func largeRemainingLength() {
        let packet = Packet.publish(Publish(
            topic: topic("t"),
            payload: Array(repeating: 0xAB, count: 20_000),
            delivery: .atMostOnce,
            retain: false,
            duplicate: false,
            properties: []
        ))
        let encoded = (try? packet.encode(for: .v5).get()) ?? []
        #expect(Array(encoded.prefix(4)) == [0x30, 0xA4, 0x9C, 0x01])
        #expect(Packet.decode(encoded, for: .v5) == .success(packet))
    }
}

@Suite struct CodecVersionRulesTests {
    @Test func propertiesAreRejectedInV311() {
        let packet = Packet.disconnect(Disconnect(reasonCode: .normalDisconnection, properties: [.reasonString("bye")]))
        #expect(packet.encode(for: .v3_1_1) == .failure(.unsupported(.properties, in: .v3_1_1)))
    }

    @Test func reasonCodesWithoutEquivalentAreRejectedInV311() {
        let packet = Packet.pubAck(Acknowledgement(packetIdentifier: id(1), reasonCode: .quotaExceeded, properties: []))
        #expect(packet.encode(for: .v3_1_1) == .failure(.unsupported(.reasonCode(.quotaExceeded), in: .v3_1_1)))
        let refused = Packet.connAck(ConnAck(sessionPresent: false, reasonCode: .banned, properties: []))
        #expect(refused.encode(for: .v3_1_1) == .failure(.unsupported(.reasonCode(.banned), in: .v3_1_1)))
    }

    @Test func subAckFailuresCollapseToX80InV311() {
        let packet = Packet.subAck(SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS2, .topicFilterInvalid], properties: []))
        #expect(packet.encode(for: .v3_1_1) == .success([0x90, 0x04, 0x00, 0x01, 0x02, 0x80]))
    }

    @Test func authIsV5Only() {
        let packet = Packet.auth(Auth(reasonCode: .success, properties: []))
        #expect(packet.encode(for: .v3_1_1) == .failure(.unsupported(.authPacket, in: .v3_1_1)))
        #expect(Packet.decode([0xF0, 0x00], for: .v3_1_1) == .failure(.reservedPacketType(15)))
        #expect(Packet.decode([0xF0, 0x00], for: .v5) == .success(.auth(Auth(reasonCode: .success, properties: []))))
    }

    @Test func subscriptionOptionsAreV5Only() {
        let options = SubscriptionOptions(qos: .atMostOnce, noLocal: true, retainAsPublished: false, retainHandling: .sendOnSubscribe)
        let packet = Packet.subscribe(Subscribe(
            packetIdentifier: id(1),
            subscriptions: [Subscription(filter: filter("a"), options: options)],
            properties: []
        ))
        #expect(packet.encode(for: .v3_1_1) == .failure(.unsupported(.subscriptionOptions, in: .v3_1_1)))
    }

    @Test func passwordWithoutUserNameIsV5Only() {
        let connect = Connect(
            protocolVersion: .v3_1_1,
            clientIdentifier: "c",
            cleanStart: true,
            keepAlive: 0,
            will: nil,
            userName: nil,
            password: [1],
            properties: []
        )
        #expect(Packet.connect(connect).encode(for: .v3_1_1) == .failure(.unsupported(.passwordWithoutUserName, in: .v3_1_1)))
    }

    @Test func connectAnnouncesItsOwnVersion() {
        let connect = Connect(
            protocolVersion: .v5,
            clientIdentifier: "c",
            cleanStart: true,
            keepAlive: 0,
            will: nil,
            userName: nil,
            password: nil,
            properties: [.sessionExpiryInterval(1)]
        )
        let encoded = (try? Packet.connect(connect).encode(for: .v3_1_1).get()) ?? []
        #expect(Packet.decode(encoded, for: .v3_1_1) == .success(.connect(connect)))
    }
}

@Suite struct CodecMalformedInputTests {
    @Test func reservedPacketTypeZero() {
        #expect(Packet.decode([0x00, 0x00], for: .v5) == .failure(.reservedPacketType(0)))
    }

    @Test func wrongFixedFlags() {
        #expect(Packet.decode([0x80, 0x00], for: .v5) == .failure(.invalidFlags(.subscribe, 0)))
        #expect(Packet.decode([0xC1, 0x00], for: .v5) == .failure(.invalidFlags(.pingReq, 1)))
    }

    @Test func qos3() {
        #expect(Packet.decode([0x36, 0x03, 0x00, 0x01, 0x61], for: .v5) == .failure(.invalidQoS(3)))
    }

    @Test func duplicateQoS0() {
        #expect(Packet.decode([0x38, 0x03, 0x00, 0x01, 0x61], for: .v3_1_1) == .failure(.invalidFlags(.publish, 8)))
    }

    @Test func zeroPacketIdentifier() {
        #expect(Packet.decode([0x40, 0x02, 0x00, 0x00], for: .v3_1_1) == .failure(.zeroPacketIdentifier))
    }

    @Test func wildcardInTopicName() {
        #expect(Packet.decode([0x30, 0x03, 0x00, 0x01, 0x23], for: .v3_1_1) == .failure(.invalidTopicName("#")))
    }

    @Test func emptyTopicNameInV311() {
        #expect(Packet.decode([0x30, 0x02, 0x00, 0x00], for: .v3_1_1) == .failure(.invalidTopicName("")))
    }

    @Test func emptySubscribe() {
        #expect(Packet.decode([0x82, 0x02, 0x00, 0x01], for: .v3_1_1) == .failure(.emptyTopicList(.subscribe)))
    }

    @Test func badProtocolName() {
        #expect(
            Packet.decode(bytes("10 0c 00 04 4d 51 49 73 04 02 00 00 00 00"), for: .v3_1_1)
                == .failure(.invalidProtocolName("MQIs"))
        )
    }

    @Test func unsupportedProtocolLevel() {
        #expect(
            Packet.decode(bytes("10 0c 00 04 4d 51 54 54 03 02 00 00 00 00"), for: .v3_1_1)
                == .failure(.unsupportedProtocolLevel(3))
        )
    }

    @Test func unknownProperty() {
        #expect(Packet.decode([0xE0, 0x03, 0x00, 0x01, 0x7F], for: .v5) == .failure(.unknownProperty(0x7F)))
    }

    @Test func truncatedBody() {
        #expect(Packet.decode([0x40, 0x02, 0x00], for: .v5) == .failure(.binary(.unexpectedEnd(needed: 2, offset: 2))))
    }

    @Test func trailingBytesInsideRemainingLength() {
        #expect(Packet.decode([0xC0, 0x01, 0x00], for: .v5) == .failure(.binary(.trailingBytes(count: 1, offset: 2))))
    }
}
