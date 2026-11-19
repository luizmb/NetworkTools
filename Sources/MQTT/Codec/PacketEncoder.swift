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
    static func encoder(for version: ProtocolVersion) -> MQTTEncoder<Packet> {
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
            Wire.require({ $0.password == nil || $0.userName != nil || version == .v5 }, .unsupported(.passwordWithoutUserName, in: version))
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

// MARK: - Wire primitives

enum Wire {
    static let byte: MQTTEncoder<UInt8> = .byte
    static let uint16: MQTTEncoder<UInt16> = .integer(.big)
    static let uint32: MQTTEncoder<UInt32> = .integer(.big)
    static let variableByteInteger: MQTTEncoder<UInt32> = .variableLength(maxBytes: 4)
    static let reasonCode: MQTTEncoder<ReasonCode> = byte.contramap(\.rawValue)
    static let packetIdentifier: MQTTEncoder<PacketIdentifier> = uint16.contramap(\.rawValue)

    /// A length written as a Variable Byte Integer (remaining length, property length).
    static let variableLength: MQTTEncoder<Int> = Convert { count in
        (UInt32(exactly: count).map(Result.success)
            ?? .failure(.binary(.lengthTooLarge(count: count, max: UInt64(UInt32.max)))))
            .flatMap(variableByteInteger.run)
    }

    /// UTF-8 Encoded String: two-byte length, then the bytes. Rejects U+0000.
    static let string: MQTTEncoder<String> =
        require({ !$0.contains("\u{0000}") }, { .nullCharacter($0) })
            <> ByteEncoders.prefixed(by: ByteEncoders.length(UInt16.self, .big), .utf8)

    /// Binary Data: two-byte length, then the bytes.
    static let binary: MQTTEncoder<[UInt8]> = ByteEncoders.prefixed(by: ByteEncoders.length(UInt16.self, .big), .raw)

    /// UTF-8 String Pair (User Property).
    static let stringPair: MQTTEncoder<(name: String, value: String)> =
        string.contramap(\.name) <> string.contramap(\.value)

    static func topicName(_ version: ProtocolVersion) -> MQTTEncoder<TopicName> {
        require({ version == .v5 || !$0.rawValue.isEmpty }, .unsupported(.emptyTopicName, in: version))
            <> string.contramap(\.rawValue)
    }

    /// The property list: Variable Byte Integer length, then the properties. MQTT 3.1.1 writes
    /// nothing and rejects a non-empty list.
    static func properties(_ version: ProtocolVersion) -> MQTTEncoder<[Property]> {
        switch version {
        case .v3_1_1: require(\.isEmpty, .unsupported(.properties, in: version))
        case .v5: ByteEncoders.prefixed(by: variableLength, ByteEncoders.many(property))
        }
    }

    static let property: MQTTEncoder<Property> = variableByteInteger.contramap { UInt32($0.identifier) } <> propertyValue

    static let propertyValue: MQTTEncoder<Property> = Convert { property in
        switch property {
        case let .payloadFormatIndicator(value), let .requestProblemInformation(value),
             let .requestResponseInformation(value), let .maximumQoS(value), let .retainAvailable(value),
             let .wildcardSubscriptionAvailable(value), let .subscriptionIdentifierAvailable(value),
             let .sharedSubscriptionAvailable(value):
            byte.run(value)
        case let .serverKeepAlive(value), let .receiveMaximum(value), let .topicAliasMaximum(value), let .topicAlias(value):
            uint16.run(value)
        case let .messageExpiryInterval(value), let .sessionExpiryInterval(value), let .willDelayInterval(value),
             let .maximumPacketSize(value):
            uint32.run(value)
        case let .subscriptionIdentifier(value):
            variableByteInteger.run(value)
        case let .contentType(value), let .responseTopic(value), let .assignedClientIdentifier(value),
             let .authenticationMethod(value), let .responseInformation(value), let .serverReference(value),
             let .reasonString(value):
            string.run(value)
        case let .correlationData(value), let .authenticationData(value):
            binary.run(value)
        case let .userProperty(name, value):
            stringPair.run((name: name, value: value))
        }
    }

    /// The optional reason code + properties tail of acknowledgements, DISCONNECT and AUTH.
    ///
    /// MQTT 5 uses the shortest valid form (nothing for the default reason with no properties,
    /// the reason alone with no properties). MQTT 3.1.1 only accepts the default reason with no
    /// properties and writes nothing.
    static func reasonAndProperties(
        _ version: ProtocolVersion,
        default defaultReason: ReasonCode
    ) -> MQTTEncoder<(reason: ReasonCode, properties: [Property])> {
        switch version {
        case .v3_1_1:
            Convert { tail in
                tail.reason != defaultReason ? .failure(.unsupported(.reasonCode(tail.reason), in: version))
                    : !tail.properties.isEmpty ? .failure(.unsupported(.properties, in: version))
                    : .success([])
            }
        case .v5:
            Convert { tail in
                tail.properties.isEmpty
                    ? (tail.reason == defaultReason ? .success([]) : reasonCode.run(tail.reason))
                    : (reasonCode.contramap(\.reason) <> properties(version).contramap(\.properties)).run(tail)
            }
        }
    }

    /// Fixed header + Remaining Length + body.
    static func framed<A>(_ type: PacketType, flags: @escaping (A) -> UInt8, _ body: MQTTEncoder<A>) -> MQTTEncoder<A> {
        byte.contramap { type.rawValue << 4 | flags($0) } <> ByteEncoders.prefixed(by: variableLength, body)
    }

    /// Fixed header + Remaining Length + body, with the flags the packet type requires.
    static func framed<A>(_ type: PacketType, _ body: MQTTEncoder<A>) -> MQTTEncoder<A> {
        framed(type, flags: const(type.requiredFlags ?? 0), body)
    }

    /// Writes nothing when `predicate` holds, fails otherwise.
    static func require<A>(_ predicate: @escaping (A) -> Bool, _ error: MQTTEncodingError) -> MQTTEncoder<A> {
        require(predicate, const(error))
    }

    /// Writes nothing when `predicate` holds, fails with an error built from the input otherwise.
    static func require<A>(_ predicate: @escaping (A) -> Bool, _ error: @escaping (A) -> MQTTEncodingError) -> MQTTEncoder<A> {
        Convert { predicate($0) ? .success([]) : .failure(error($0)) }
    }
}

extension SubscriptionOptions {
    /// The subscription options byte.
    var byte: UInt8 {
        qos.rawValue | (noLocal ? 0b0100 : 0) | (retainAsPublished ? 0b1000 : 0) | retainHandling.rawValue << 4
    }
}
