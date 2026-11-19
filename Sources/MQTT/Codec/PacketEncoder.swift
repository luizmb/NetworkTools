// SPDX-License-Identifier: Apache-2.0

import Core
import FP

/// An MQTT encoder: a ``Core/ByteEncoder`` failing with ``MQTTEncodingError``.
public typealias MQTTEncoder<A> = ByteEncoder<A, MQTTEncodingError>

public extension Packet {
    /// The encoder of whole packets (fixed header included) for a protocol version.
    ///
    /// CONNECT is always written in its own ``Connect/protocolVersion``; every other packet uses
    /// `version`. Anything `version` cannot express fails with
    /// ``MQTTEncodingError/unsupported(_:in:)`` rather than being dropped.
    /// - Parameter version: The connection's protocol version.
    /// - Returns: The packet encoder.
    static func encoder(for version: ProtocolVersion) -> MQTTEncoder<Packet> { // swiftlint:disable:this cyclomatic_complexity
        Convert { packet in
            switch packet {
            case let .connect(value): Encoders.connect.run(value)
            case let .connAck(value): Encoders.connAck(version).run(value)
            case let .publish(value): Encoders.publish(version).run(value)
            case let .pubAck(value): Encoders.acknowledgement(.pubAck, version).run(value)
            case let .pubRec(value): Encoders.acknowledgement(.pubRec, version).run(value)
            case let .pubRel(value): Encoders.acknowledgement(.pubRel, version).run(value)
            case let .pubComp(value): Encoders.acknowledgement(.pubComp, version).run(value)
            case let .subscribe(value): Encoders.subscribe(version).run(value)
            case let .subAck(value): Encoders.subAck(version).run(value)
            case let .unsubscribe(value): Encoders.unsubscribe(version).run(value)
            case let .unsubAck(value): Encoders.unsubAck(version).run(value)
            case .pingReq: Encoders.empty(.pingReq).run(())
            case .pingResp: Encoders.empty(.pingResp).run(())
            case let .disconnect(value): Encoders.disconnect(version).run(value)
            case let .auth(value): Encoders.auth(version).run(value)
            }
        }
    }

    /// Encodes this packet for a protocol version.
    /// - Parameter version: The connection's protocol version.
    /// - Returns: The packet's bytes, or why it cannot be encoded.
    func encode(for version: ProtocolVersion) -> Result<[UInt8], MQTTEncodingError> {
        Packet.encoder(for: version).run(self)
    }
}

// MARK: - Packet encoders

enum Encoders {
    static let connect: MQTTEncoder<Connect> = Convert { connect in
        let version = connect.protocolVersion
        let body: MQTTEncoder<Connect> =
            Wire.require(
                { $0.password == nil || $0.userName != nil || version == .v5 },
                .unsupported(.passwordWithoutUserName, in: version)
            )
            <> Wire.string.contramap(const("MQTT"))
            <> Wire.byte.contramap(const(version.rawValue))
            <> Wire.byte.contramap(connectFlags)
            <> Wire.uint16.contramap(\.keepAlive)
            <> Wire.properties(version).contramap(\.properties)
            <> Wire.string.contramap(\.clientIdentifier)
            <> ByteEncoders.optional(will(version)).contramap(\.will)
            <> ByteEncoders.optional(Wire.string).contramap(\.userName)
            <> ByteEncoders.optional(Wire.binary).contramap(\.password)
        return Wire.framed(.connect, body).run(connect)
    }

    static func will(_ version: ProtocolVersion) -> MQTTEncoder<Will> {
        Wire.properties(version).contramap(\.properties)
            <> Wire.topicName(version).contramap(\.topic)
            <> Wire.binary.contramap(\.payload)
    }

    static func connAck(_ version: ProtocolVersion) -> MQTTEncoder<ConnAck> {
        let code: MQTTEncoder<ReasonCode> = switch version {
        case .v3_1_1:
            Convert { reason in
                reason.connectReturnCode.map { [$0] }.map(Result.success)
                    ?? .failure(.unsupported(.reasonCode(reason), in: version))
            }
        case .v5:
            Wire.reasonCode
        }
        return Wire.framed(
            .connAck,
            Wire.byte.contramap { $0.sessionPresent ? 1 : 0 }
                <> code.contramap(\.reasonCode)
                <> Wire.properties(version).contramap(\.properties)
        )
    }

    static func publish(_ version: ProtocolVersion) -> MQTTEncoder<Publish> {
        Wire.framed(
            .publish,
            flags: { ($0.duplicate ? 0b1000 : 0) | $0.delivery.qos.rawValue << 1 | ($0.retain ? 1 : 0) },
            Wire.topicName(version).contramap(\.topic)
                <> ByteEncoders.optional(Wire.packetIdentifier).contramap(\.delivery.packetIdentifier)
                <> Wire.properties(version).contramap(\.properties)
                <> MQTTEncoder<[UInt8]>.raw.contramap(\.payload)
        )
    }

    static func acknowledgement(_ type: PacketType, _ version: ProtocolVersion) -> MQTTEncoder<Acknowledgement> {
        Wire.framed(
            type,
            Wire.packetIdentifier.contramap(\.packetIdentifier)
                <> Wire.reasonAndProperties(version, default: .success)
                .contramap { (reason: $0.reasonCode, properties: $0.properties) }
        )
    }

    static func subscribe(_ version: ProtocolVersion) -> MQTTEncoder<Subscribe> {
        Wire.framed(
            .subscribe,
            Wire.require({ !$0.subscriptions.isEmpty }, .emptyTopicList(.subscribe))
                <> Wire.packetIdentifier.contramap(\.packetIdentifier)
                <> Wire.properties(version).contramap(\.properties)
                <> ByteEncoders.many(subscription(version)).contramap(\.subscriptions)
        )
    }

    static func subscription(_ version: ProtocolVersion) -> MQTTEncoder<Subscription> {
        Wire.require({ version == .v5 || $0.options.isQoSOnly }, .unsupported(.subscriptionOptions, in: version))
            <> Wire.string.contramap(\.filter.rawValue)
            <> Wire.byte.contramap(\.options.byte)
    }

    static func subAck(_ version: ProtocolVersion) -> MQTTEncoder<SubAck> {
        let code: MQTTEncoder<ReasonCode> = switch version {
        case .v3_1_1: Wire.byte.contramap(\.subAckReturnCode)
        case .v5: Wire.reasonCode
        }
        return Wire.framed(
            .subAck,
            Wire.packetIdentifier.contramap(\.packetIdentifier)
                <> Wire.properties(version).contramap(\.properties)
                <> ByteEncoders.many(code).contramap(\.reasonCodes)
        )
    }

    static func unsubscribe(_ version: ProtocolVersion) -> MQTTEncoder<Unsubscribe> {
        Wire.framed(
            .unsubscribe,
            Wire.require({ !$0.filters.isEmpty }, .emptyTopicList(.unsubscribe))
                <> Wire.packetIdentifier.contramap(\.packetIdentifier)
                <> Wire.properties(version).contramap(\.properties)
                <> ByteEncoders.many(Wire.string.contramap(\TopicFilter.rawValue)).contramap(\.filters)
        )
    }

    static func unsubAck(_ version: ProtocolVersion) -> MQTTEncoder<UnsubAck> {
        let codes: MQTTEncoder<[ReasonCode]> = switch version {
        case .v3_1_1:
            Convert { codes in
                codes.first(where: \.isFailure)
                    .map { .failure(.unsupported(.reasonCode($0), in: version)) } ?? .success([])
            }
        case .v5:
            ByteEncoders.many(Wire.reasonCode)
        }
        return Wire.framed(
            .unsubAck,
            Wire.packetIdentifier.contramap(\.packetIdentifier)
                <> Wire.properties(version).contramap(\.properties)
                <> codes.contramap(\.reasonCodes)
        )
    }

    static func disconnect(_ version: ProtocolVersion) -> MQTTEncoder<Disconnect> {
        Wire.framed(
            .disconnect,
            Wire.reasonAndProperties(version, default: .normalDisconnection)
                .contramap { (reason: $0.reasonCode, properties: $0.properties) }
        )
    }

    static func auth(_ version: ProtocolVersion) -> MQTTEncoder<Auth> {
        Wire.require(const(version == .v5), .unsupported(.authPacket, in: version))
            <> Wire.framed(
                .auth,
                Wire.reasonAndProperties(version, default: .success)
                    .contramap { (reason: $0.reasonCode, properties: $0.properties) }
            )
    }

    static func empty(_ type: PacketType) -> MQTTEncoder<Void> {
        Wire.framed(type, .identity)
    }

    private static func connectFlags(_ connect: Connect) -> UInt8 {
        (connect.userName == nil ? 0 : 0b1000_0000)
            | (connect.password == nil ? 0 : 0b0100_0000)
            | (connect.will.map { ($0.retain ? 0b0010_0000 : 0) | $0.qos.rawValue << 3 | 0b0000_0100 } ?? 0)
            | (connect.cleanStart ? 0b0000_0010 : 0)
    }
}
