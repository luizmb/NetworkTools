// SPDX-License-Identifier: Apache-2.0

import Core

/// Why bytes could not be decoded into a ``Packet``.
public enum MQTTDecodingError: Error, Sendable, Hashable, ByteParseFailure {
    /// A byte-level failure (truncated field, bad UTF-8, malformed variable-length integer, …).
    case binary(BinaryParseError)
    /// The packet type nibble is `0`, or `15` (AUTH) on an MQTT 3.1.1 connection.
    case reservedPacketType(UInt8)
    /// The fixed-header flags are not the ones the packet type requires.
    case invalidFlags(PacketType, UInt8)
    /// The CONNECT protocol name is not `MQTT`.
    case invalidProtocolName(String)
    /// The CONNECT protocol level is not 4 (3.1.1) or 5.
    case unsupportedProtocolLevel(UInt8)
    /// Reserved or contradictory CONNECT flags.
    case invalidConnectFlags(UInt8)
    /// A QoS of 3.
    case invalidQoS(UInt8)
    /// A packet identifier of `0`.
    case zeroPacketIdentifier
    /// A topic name that is empty (3.1.1) or contains wildcards or a null character.
    case invalidTopicName(String)
    /// A topic filter that breaks the wildcard rules.
    case invalidTopicFilter(String)
    /// A string containing the null character U+0000.
    case nullCharacter(offset: Int)
    /// An unknown MQTT 5 property identifier.
    case unknownProperty(UInt32)
    /// An MQTT 3.1.1 CONNACK return code above 5.
    case unknownConnectReturnCode(UInt8)
    /// Reserved bits set in subscription options.
    case invalidSubscriptionOptions(UInt8)
    /// A SUBSCRIBE or UNSUBSCRIBE without any topic filter.
    case emptyTopicList(PacketType)
}

/// Why a ``Packet`` could not be encoded.
public enum MQTTEncodingError: Error, Sendable, Hashable, ByteEncodeFailure {
    /// A byte-level failure (string or packet too long for its length field).
    case binary(BinaryEncodeError)
    /// The packet uses something the target protocol version cannot express.
    case unsupported(UnsupportedFeature, in: ProtocolVersion)
    /// A string containing the null character U+0000.
    case nullCharacter(String)
    /// A SUBSCRIBE or UNSUBSCRIBE without any topic filter.
    case emptyTopicList(PacketType)
}

/// Things MQTT 5 can say that MQTT 3.1.1 cannot.
public enum UnsupportedFeature: Sendable, Hashable {
    /// A non-empty property list.
    case properties
    /// A reason code with no 3.1.1 equivalent in that packet.
    case reasonCode(ReasonCode)
    /// The AUTH packet.
    case authPacket
    /// Subscription options other than QoS.
    case subscriptionOptions
    /// A password without a user name.
    case passwordWithoutUserName
    /// An empty topic name (only meaningful with an MQTT 5 Topic Alias).
    case emptyTopicName
}
