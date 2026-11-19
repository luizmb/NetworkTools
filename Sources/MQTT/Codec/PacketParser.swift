// SPDX-License-Identifier: Apache-2.0

import Core
import FP

/// An MQTT parser: a ``Core/ByteParser`` failing with ``MQTTDecodingError``.
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

// MARK: - Field readers

enum Read {
    static let byte: MQTTParser<UInt8> = .byte
    static let uint16: MQTTParser<UInt16> = .integer(.big)
    static let uint32: MQTTParser<UInt32> = .integer(.big)
    static let variableByteInteger: MQTTParser<UInt32> = .variableLength(maxBytes: 4)
    static let reasonCode: MQTTParser<ReasonCode> = byte.map(ReasonCode.init(rawValue:))

    static let packetIdentifier: MQTTParser<PacketIdentifier> = uint16.refine { raw in
        PacketIdentifier(rawValue: raw).map(Result.success) ?? .failure(.zeroPacketIdentifier)
    }

    /// UTF-8 Encoded String: two-byte length, then the bytes. Rejects U+0000.
    static let string: MQTTParser<String> = MQTTParser<Int>.offset >>- { offset in
        uint16 >>- { length in
            MQTTParser<String>.utf8(count: Int(length))
                .ensure({ !$0.contains("\u{0000}") }, else: const(.nullCharacter(offset: offset)))
        }
    }

    /// Binary Data: two-byte length, then the bytes.
    static let binary: MQTTParser<[UInt8]> = uint16 >>- { MQTTParser<[UInt8]>.bytes(count: Int($0)) }

    static func topicName(_ version: ProtocolVersion) -> MQTTParser<TopicName> {
        string.refine { raw in
            TopicName(rawValue: raw).flatMap { version == .v5 || !raw.isEmpty ? $0 : nil }
                .map(Result.success) ?? .failure(.invalidTopicName(raw))
        }
    }

    static let topicFilter: MQTTParser<TopicFilter> = string.refine { raw in
        TopicFilter(rawValue: raw).map(Result.success) ?? .failure(.invalidTopicFilter(raw))
    }

    /// The property list (MQTT 5): Variable Byte Integer length, then the properties.
    /// MQTT 3.1.1 has no property list and reads nothing.
    static func properties(_ version: ProtocolVersion) -> MQTTParser<[Property]> {
        switch version {
        case .v3_1_1: .pure([])
        case .v5: variableByteInteger >>- { ByteParsers.isolate(Int($0), ByteParsers.manyUntilEnd(property)) }
        }
    }

    static let property: MQTTParser<Property> = variableByteInteger >>- propertyValue

    // swiftlint:disable:next cyclomatic_complexity
    static func propertyValue(_ identifier: UInt32) -> MQTTParser<Property> {
        switch identifier {
        case 0x01: byte.map(Property.payloadFormatIndicator)
        case 0x02: uint32.map(Property.messageExpiryInterval)
        case 0x03: string.map(Property.contentType)
        case 0x08: string.map(Property.responseTopic)
        case 0x09: binary.map(Property.correlationData)
        case 0x0B: variableByteInteger.map(Property.subscriptionIdentifier)
        case 0x11: uint32.map(Property.sessionExpiryInterval)
        case 0x12: string.map(Property.assignedClientIdentifier)
        case 0x13: uint16.map(Property.serverKeepAlive)
        case 0x15: string.map(Property.authenticationMethod)
        case 0x16: binary.map(Property.authenticationData)
        case 0x17: byte.map(Property.requestProblemInformation)
        case 0x18: uint32.map(Property.willDelayInterval)
        case 0x19: byte.map(Property.requestResponseInformation)
        case 0x1A: string.map(Property.responseInformation)
        case 0x1C: string.map(Property.serverReference)
        case 0x1F: string.map(Property.reasonString)
        case 0x21: uint16.map(Property.receiveMaximum)
        case 0x22: uint16.map(Property.topicAliasMaximum)
        case 0x23: uint16.map(Property.topicAlias)
        case 0x24: byte.map(Property.maximumQoS)
        case 0x25: byte.map(Property.retainAvailable)
        case 0x26: MQTTParser<Property>.liftA2(Property.userProperty)(string, string)
        case 0x27: uint32.map(Property.maximumPacketSize)
        case 0x28: byte.map(Property.wildcardSubscriptionAvailable)
        case 0x29: byte.map(Property.subscriptionIdentifierAvailable)
        case 0x2A: byte.map(Property.sharedSubscriptionAvailable)
        default: .fail(.unknownProperty(identifier))
        }
    }
}

// MARK: - Flag bytes

/// The decoded CONNECT flags byte.
struct ConnectFlags: Sendable {
    let userName: Bool
    let password: Bool
    let will: (qos: QoS, retain: Bool)?
    let cleanStart: Bool

    static func parse(_ version: ProtocolVersion) -> @Sendable (UInt8) -> Result<ConnectFlags, MQTTDecodingError> {
        { byte in
            let hasWill = byte & 0b0000_0100 != 0
            let willQoS = (byte >> 3) & 0b11
            let willRetain = byte & 0b0010_0000 != 0
            let userName = byte & 0b1000_0000 != 0
            let password = byte & 0b0100_0000 != 0
            let invalid = byte & 0b0000_0001 != 0
                || (!hasWill && (willQoS != 0 || willRetain))
                || (version == .v3_1_1 && password && !userName)
            return switch (invalid, QoS(rawValue: willQoS)) {
            case (false, let .some(qos)):
                .success(ConnectFlags(
                    userName: userName,
                    password: password,
                    will: hasWill ? (qos: qos, retain: willRetain) : nil,
                    cleanStart: byte & 0b0000_0010 != 0
                ))
            default:
                .failure(.invalidConnectFlags(byte))
            }
        }
    }
}

extension SubscriptionOptions {
    static func parse(_ version: ProtocolVersion) -> @Sendable (UInt8) -> Result<SubscriptionOptions, MQTTDecodingError> {
        { byte in
            let reserved: UInt8 = version == .v5 ? 0b1100_0000 : 0b1111_1100
            return switch (byte & reserved == 0, QoS(rawValue: byte & 0b11), RetainHandling(rawValue: (byte >> 4) & 0b11)) {
            case let (true, .some(qos), .some(retainHandling)):
                .success(SubscriptionOptions(
                    qos: qos,
                    noLocal: byte & 0b0100 != 0,
                    retainAsPublished: byte & 0b1000 != 0,
                    retainHandling: retainHandling
                ))
            default:
                .failure(.invalidSubscriptionOptions(byte))
            }
        }
    }
}
