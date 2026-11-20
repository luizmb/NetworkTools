// SPDX-License-Identifier: Apache-2.0

import Core
import FP

// MARK: - Wire primitives

enum Wire {
    static let byte: MQTTEncoder<UInt8> = .byte
    static let uint16: MQTTEncoder<UInt16> = .integer(.big)
    static let uint32: MQTTEncoder<UInt32> = .integer(.big)
    /// Lifts byte-level failures into ``MQTTEncodingError``.
    static let errors = MQTTEncodingError.prism.binary

    static let variableByteInteger: MQTTEncoder<UInt32> = ByteEncoder<UInt32, BinaryEncodeError>.variableLength(maxBytes: 4).embed(errors)
    static let length16: MQTTEncoder<Int> = ByteEncoders.length(UInt16.self, .big).embed(errors)
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
        <> ByteEncoders.prefixed(by: length16, .utf8)

    /// Binary Data: two-byte length, then the bytes.
    static let binary: MQTTEncoder<[UInt8]> = ByteEncoders.prefixed(by: length16, .raw)

    /// UTF-8 String Pair (User Property).
    static let stringPair: MQTTEncoder<(name: String, value: String)> =
        string.contramap(\.name) <> string.contramap(\.value)

    static func topicName(_ version: ProtocolVersion) -> MQTTEncoder<TopicName> {
        require({ version == .v5 || !$0.rawValue.isEmpty }, .unsupported(.emptyTopicName, in: version))
            <> string.contramap(\.rawValue)
    }

    /// The property list: Variable Byte Integer length, then the properties. MQTT 3.1.1 writes
    /// nothing and rejects a non-empty list.
    static func properties(_ version: ProtocolVersion, in context: PropertyContext) -> MQTTEncoder<[Property]> {
        switch version {
        case .v3_1_1:
            require(\.isEmpty, .unsupported(.properties, in: version))
        case .v5:
            Convert { PropertyRules.validate($0, in: context).mapError(MQTTEncodingError.invalidProperty) }
                .flatMap { valid in ByteEncoders.prefixed(by: variableLength, ByteEncoders.many(property)).contramap(const(valid)) }
        }
    }

    static let property: MQTTEncoder<Property> = variableByteInteger.contramap { UInt32($0.identifier) } <> propertyValue

    static let propertyValue: MQTTEncoder<Property> = Convert { property in
        switch property {
        case let .payloadFormatIndicator(value),
             let .requestProblemInformation(value),
             let .requestResponseInformation(value),
             let .maximumQoS(value),
             let .retainAvailable(value),
             let .wildcardSubscriptionAvailable(value),
             let .subscriptionIdentifierAvailable(value),
             let .sharedSubscriptionAvailable(value):
            byte.run(value)
        case let .serverKeepAlive(value),
             let .receiveMaximum(value),
             let .topicAliasMaximum(value),
             let .topicAlias(value):
            uint16.run(value)
        case let .messageExpiryInterval(value),
             let .sessionExpiryInterval(value),
             let .willDelayInterval(value),
             let .maximumPacketSize(value):
            uint32.run(value)
        case let .subscriptionIdentifier(value):
            variableByteInteger.run(value)
        case let .contentType(value),
             let .responseTopic(value),
             let .assignedClientIdentifier(value),
             let .authenticationMethod(value),
             let .responseInformation(value),
             let .serverReference(value),
             let .reasonString(value):
            string.run(value)
        case let .correlationData(value),
             let .authenticationData(value):
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
        default defaultReason: ReasonCode,
        in context: PropertyContext
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
                    : (reasonCode.contramap(\.reason) <> properties(version, in: context).contramap(\.properties)).run(tail)
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
