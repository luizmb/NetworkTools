// SPDX-License-Identifier: Apache-2.0

import Core
import FP

/// An MQTT parser: a `Core.ByteParser` failing with ``MQTTDecodingError``.
public typealias MQTTParser<A: Sendable> = ByteParser<A, MQTTDecodingError>

public extension Packet {
    /// The parser of one whole packet (fixed header, Remaining Length and body) for a protocol version.
    ///
    /// CONNECT is decoded in the version its own protocol-level byte announces, so a broker can
    /// decode the first packet of a connection before it knows the version.
    /// - Parameter version: The connection's protocol version.
    /// - Returns: The packet parser.
    static func parser(for version: ProtocolVersion) -> MQTTParser<Packet> {
        MQTTParser<UInt8>.byte >>- { header in
            Read.variableByteInteger >>- { length in
                ByteParsers.isolate(Int(length), Parsers.body(header: header, version: version))
            }
        }
    }

    /// Decodes exactly one packet from `bytes`.
    /// - Parameters:
    ///   - bytes: One complete packet, nothing more.
    ///   - version: The connection's protocol version.
    /// - Returns: The packet, or why the bytes are not one valid packet.
    static func decode(_ bytes: [UInt8], for version: ProtocolVersion) -> Result<Packet, MQTTDecodingError> {
        parser(for: version).parseAll(bytes)
    }
}

// MARK: - Packet bodies

enum Parsers {
    // swiftlint:disable:next cyclomatic_complexity
    static func body(header: UInt8, version: ProtocolVersion) -> MQTTParser<Packet> {
        let flags = header & 0x0F
        guard let type = PacketType(rawValue: header >> 4), type != .auth || version == .v5 else {
            return .fail(.reservedPacketType(header >> 4))
        }
        guard type.requiredFlags.map({ $0 == flags }) ?? true else {
            return .fail(.invalidFlags(type, flags))
        }
        return switch type {
        case .connect: connect.map(Packet.connect)
        case .connAck: connAck(version).map(Packet.connAck)
        case .publish: publish(flags: flags, version).map(Packet.publish)
        case .pubAck: acknowledgement(version).map(Packet.pubAck)
        case .pubRec: acknowledgement(version).map(Packet.pubRec)
        case .pubRel: acknowledgement(version).map(Packet.pubRel)
        case .pubComp: acknowledgement(version).map(Packet.pubComp)
        case .subscribe: subscribe(version).map(Packet.subscribe)
        case .subAck: subAck(version).map(Packet.subAck)
        case .unsubscribe: unsubscribe(version).map(Packet.unsubscribe)
        case .unsubAck: unsubAck(version).map(Packet.unsubAck)
        case .pingReq: MQTTParser<Packet>.pure(.pingReq)
        case .pingResp: MQTTParser<Packet>.pure(.pingResp)
        case .disconnect: reasonAndProperties(version, default: .normalDisconnection).map(Disconnect.init).map(Packet.disconnect)
        case .auth: reasonAndProperties(version, default: .success).map(Auth.init).map(Packet.auth)
        }
    }

    // MARK: CONNECT

    static let connect: MQTTParser<Connect> =
        Read.string.ensure({ $0 == "MQTT" }, else: MQTTDecodingError.invalidProtocolName)
        *> Read.byte.refine { level in
            ProtocolVersion(rawValue: level).map(Result.success) ?? .failure(.unsupportedProtocolLevel(level))
        }

        >>- { version in
            Read.byte.refine(ConnectFlags.parse(version)) >>- { flags in
                connectRest(version: version, flags: flags)
            }
        }

    private static func connectRest(version: ProtocolVersion, flags: ConnectFlags) -> MQTTParser<Connect> {
        Read.uint16 >>- { keepAlive in
            Read.properties(version) >>- { properties in
                Read.string >>- { clientIdentifier in
                    ByteParsers.when(flags.will != nil, will(version, flags: flags)) >>- { will in
                        ByteParsers.when(flags.userName, Read.string) >>- { userName in
                            ByteParsers.when(flags.password, Read.binary).map { password in
                                Connect(
                                    protocolVersion: version,
                                    clientIdentifier: clientIdentifier,
                                    cleanStart: flags.cleanStart,
                                    keepAlive: keepAlive,
                                    will: will,
                                    userName: userName,
                                    password: password,
                                    properties: properties
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private static func will(_ version: ProtocolVersion, flags: ConnectFlags) -> MQTTParser<Will> {
        Read.properties(version) >>- { properties in
            MQTTParser<Will>.liftA2 { topic, payload in
                Will(
                    topic: topic,
                    payload: payload,
                    qos: flags.will?.qos ?? .atMostOnce,
                    retain: flags.will?.retain ?? false,
                    properties: properties
                )
            }(Read.topicName(version), Read.binary)
        }
    }

    // MARK: CONNACK

    static func connAck(_ version: ProtocolVersion) -> MQTTParser<ConnAck> {
        let flags = Read.byte.ensure({ $0 & 0b1111_1110 == 0 }, else: { .invalidFlags(.connAck, $0) })
        let reason: MQTTParser<ReasonCode> = switch version {
        case .v3_1_1:
            Read.byte.refine { code in
                ReasonCode.fromConnectReturnCode(code).map(Result.success) ?? .failure(.unknownConnectReturnCode(code))
            }
        case .v5:
            Read.reasonCode
        }
        return flags >>- { ackFlags in
            MQTTParser<ConnAck>.liftA2 { reasonCode, properties in
                ConnAck(sessionPresent: ackFlags & 1 == 1, reasonCode: reasonCode, properties: properties)
            }(reason, Read.properties(version))
        }
    }

    // MARK: PUBLISH

    static func publish(flags: UInt8, _ version: ProtocolVersion) -> MQTTParser<Publish> {
        let duplicate = flags & 0b1000 != 0
        let retain = flags & 0b0001 != 0
        guard let qos = QoS(rawValue: (flags >> 1) & 0b11) else {
            return .fail(.invalidQoS((flags >> 1) & 0b11))
        }
        guard qos != .atMostOnce || !duplicate else {
            return .fail(.invalidFlags(.publish, flags))
        }
        return Read.topicName(version) >>- { topic in
            delivery(qos) >>- { delivery in
                MQTTParser<Publish>.liftA2 { properties, payload in
                    Publish(
                        topic: topic,
                        payload: payload,
                        delivery: delivery,
                        retain: retain,
                        duplicate: duplicate,
                        properties: properties
                    )
                }(Read.properties(version), MQTTParser<[UInt8]>.rest)
            }
        }
    }

    private static func delivery(_ qos: QoS) -> MQTTParser<Delivery> {
        switch qos {
        case .atMostOnce: .pure(.atMostOnce)
        case .atLeastOnce: Read.packetIdentifier.map(Delivery.atLeastOnce)
        case .exactlyOnce: Read.packetIdentifier.map(Delivery.exactlyOnce)
        }
    }

    // MARK: Acknowledgements

    static func acknowledgement(_ version: ProtocolVersion) -> MQTTParser<Acknowledgement> {
        MQTTParser<Acknowledgement>.liftA2 { identifier, tail in
            Acknowledgement(packetIdentifier: identifier, reasonCode: tail.reason, properties: tail.properties)
        }(Read.packetIdentifier, reasonAndProperties(version, default: .success))
    }

    /// The optional reason code + properties tail: absent means the default reason, a lone byte
    /// means a reason without properties. MQTT 3.1.1 has neither.
    static func reasonAndProperties(
        _ version: ProtocolVersion,
        default defaultReason: ReasonCode
    ) -> MQTTParser<(reason: ReasonCode, properties: [Property])> {
        switch version {
        case .v3_1_1:
            .pure((reason: defaultReason, properties: []))
        case .v5:
            MQTTParser<Bool>.isAtEnd >>- { atEnd in
                atEnd
                    ? .pure((reason: defaultReason, properties: []))
                    : Read.reasonCode >>- { reason in
                        MQTTParser<Bool>.isAtEnd >>- { noProperties in
                            noProperties
                                ? .pure((reason: reason, properties: []))
                                : Read.properties(version).map { (reason: reason, properties: $0) }
                        }
                    }
            }
        }
    }

    // MARK: SUBSCRIBE / UNSUBSCRIBE

    static func subscribe(_ version: ProtocolVersion) -> MQTTParser<Subscribe> {
        Read.packetIdentifier >>- { identifier in
            MQTTParser<Subscribe>.liftA2 { properties, subscriptions in
                Subscribe(packetIdentifier: identifier, subscriptions: subscriptions, properties: properties)
            }(
                Read.properties(version),
                ByteParsers.manyUntilEnd(subscription(version))
                    .ensure({ !$0.isEmpty }, else: const(.emptyTopicList(.subscribe)))
            )
        }
    }

    static func subscription(_ version: ProtocolVersion) -> MQTTParser<Subscription> {
        MQTTParser<Subscription>.liftA2(Subscription.init)(
            Read.topicFilter,
            Read.byte.refine(SubscriptionOptions.parse(version))
        )
    }

    static func subAck(_ version: ProtocolVersion) -> MQTTParser<SubAck> {
        Read.packetIdentifier >>- { identifier in
            MQTTParser<SubAck>.liftA2 { properties, codes in
                SubAck(packetIdentifier: identifier, reasonCodes: codes, properties: properties)
            }(Read.properties(version), ByteParsers.manyUntilEnd(Read.reasonCode))
        }
    }

    static func unsubscribe(_ version: ProtocolVersion) -> MQTTParser<Unsubscribe> {
        Read.packetIdentifier >>- { identifier in
            MQTTParser<Unsubscribe>.liftA2 { properties, filters in
                Unsubscribe(packetIdentifier: identifier, filters: filters, properties: properties)
            }(
                Read.properties(version),
                ByteParsers.manyUntilEnd(Read.topicFilter)
                    .ensure({ !$0.isEmpty }, else: const(.emptyTopicList(.unsubscribe)))
            )
        }
    }

    static func unsubAck(_ version: ProtocolVersion) -> MQTTParser<UnsubAck> {
        Read.packetIdentifier >>- { identifier in
            MQTTParser<UnsubAck>.liftA2 { properties, codes in
                UnsubAck(packetIdentifier: identifier, reasonCodes: codes, properties: properties)
            }(Read.properties(version), version == .v5 ? ByteParsers.manyUntilEnd(Read.reasonCode) : .pure([]))
        }
    }
}
