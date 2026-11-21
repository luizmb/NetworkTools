// SPDX-License-Identifier: Apache-2.0

import Core
import FP

// MARK: - Field readers

enum Read {
    /// Lifts byte-level failures into ``MQTTDecodingError``.
    static let errors = MQTTDecodingError.prism.binary

    static let byte: MQTTParser<UInt8> = BinaryParser<UInt8>.byte.embed(errors)
    static let uint16: MQTTParser<UInt16> = BinaryParser<UInt16>.integer(.big).embed(errors)
    static let uint32: MQTTParser<UInt32> = BinaryParser<UInt32>.integer(.big).embed(errors)
    static let variableByteInteger: MQTTParser<UInt32> = BinaryParser<UInt32>.variableLength(maxBytes: 4).embed(errors)
    static let reasonCode: MQTTParser<ReasonCode> = byte.map(ReasonCode.init(rawValue:))

    static let packetIdentifier: MQTTParser<PacketIdentifier> = uint16.refine { raw in
        PacketIdentifier(rawValue: raw).map(Result.success) ?? .failure(.zeroPacketIdentifier)
    }

    /// UTF-8 Encoded String: two-byte length, then the bytes. Rejects U+0000.
    static let string: MQTTParser<String> = MQTTParser<Int>.offset >>- { offset in
        uint16 >>- { length in
            BinaryParser<String>
                .utf8(count: Int(length))
                .embed(errors)
                .ensure({ !$0.contains("\u{0000}") }, else: const(.nullCharacter(offset: offset)))
        }
    }

    /// Binary Data: two-byte length, then the bytes.
    static let binary: MQTTParser<[UInt8]> = uint16 >>- { BinaryParser<[UInt8]>.bytes(count: Int($0)).embed(errors) }

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
    static func properties(_ version: ProtocolVersion, in context: PropertyContext) -> MQTTParser<[Property]> {
        switch version {
        case .v3_1_1: .pure([])
        case .v5:
            variableByteInteger >>- { length in
                ByteParsers.isolate(Int(length), ByteParsers.manyUntilEnd(property, errors: errors), errors: errors)
                    .refine { PropertyRules.validate($0, in: context).mapError(MQTTDecodingError.invalidProperty) }
            }
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
