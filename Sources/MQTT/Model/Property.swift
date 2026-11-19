// SPDX-License-Identifier: Apache-2.0

/// An MQTT 5 property: optional, typed metadata attached to most packets.
///
/// Properties are encoded as an identifier followed by a value whose type is fixed by the
/// identifier. Packets carry them as an ordered list (`[Property]`), which keeps duplicates
/// that the spec allows (User Property, Subscription Identifier) and composes as a `Monoid`
/// under `<>`.
///
/// MQTT 3.1.1 has no properties: encoding a non-empty list for a 3.1.1 connection fails with
/// ``MQTTEncodingError/unsupported(_:in:)``.
public enum Property: Sendable, Hashable {
    /// `0x01` Payload Format Indicator: `0` unspecified bytes, `1` UTF-8 text.
    case payloadFormatIndicator(UInt8)
    /// `0x02` Message Expiry Interval, in seconds.
    case messageExpiryInterval(UInt32)
    /// `0x03` Content Type (e.g. a MIME type).
    case contentType(String)
    /// `0x08` Response Topic for request/response.
    case responseTopic(String)
    /// `0x09` Correlation Data for request/response.
    case correlationData([UInt8])
    /// `0x0B` Subscription Identifier.
    case subscriptionIdentifier(UInt32)
    /// `0x11` Session Expiry Interval, in seconds.
    case sessionExpiryInterval(UInt32)
    /// `0x12` Assigned Client Identifier (CONNACK).
    case assignedClientIdentifier(String)
    /// `0x13` Server Keep Alive, in seconds (CONNACK).
    case serverKeepAlive(UInt16)
    /// `0x15` Authentication Method.
    case authenticationMethod(String)
    /// `0x16` Authentication Data.
    case authenticationData([UInt8])
    /// `0x17` Request Problem Information (`0` or `1`).
    case requestProblemInformation(UInt8)
    /// `0x18` Will Delay Interval, in seconds.
    case willDelayInterval(UInt32)
    /// `0x19` Request Response Information (`0` or `1`).
    case requestResponseInformation(UInt8)
    /// `0x1A` Response Information (CONNACK).
    case responseInformation(String)
    /// `0x1C` Server Reference.
    case serverReference(String)
    /// `0x1F` Reason String: human-readable diagnostics.
    case reasonString(String)
    /// `0x21` Receive Maximum: in-flight QoS 1/2 publishes the sender accepts.
    case receiveMaximum(UInt16)
    /// `0x22` Topic Alias Maximum.
    case topicAliasMaximum(UInt16)
    /// `0x23` Topic Alias.
    case topicAlias(UInt16)
    /// `0x24` Maximum QoS (`0` or `1`; absent means `2`).
    case maximumQoS(UInt8)
    /// `0x25` Retain Available (`0` or `1`).
    case retainAvailable(UInt8)
    /// `0x26` User Property: an application-defined name/value pair. May repeat.
    case userProperty(name: String, value: String)
    /// `0x27` Maximum Packet Size, in bytes.
    case maximumPacketSize(UInt32)
    /// `0x28` Wildcard Subscription Available (`0` or `1`).
    case wildcardSubscriptionAvailable(UInt8)
    /// `0x29` Subscription Identifier Available (`0` or `1`).
    case subscriptionIdentifierAvailable(UInt8)
    /// `0x2A` Shared Subscription Available (`0` or `1`).
    case sharedSubscriptionAvailable(UInt8)

    /// The property identifier on the wire.
    public var identifier: UInt8 {
        switch self {
        case .payloadFormatIndicator: 0x01
        case .messageExpiryInterval: 0x02
        case .contentType: 0x03
        case .responseTopic: 0x08
        case .correlationData: 0x09
        case .subscriptionIdentifier: 0x0B
        case .sessionExpiryInterval: 0x11
        case .assignedClientIdentifier: 0x12
        case .serverKeepAlive: 0x13
        case .authenticationMethod: 0x15
        case .authenticationData: 0x16
        case .requestProblemInformation: 0x17
        case .willDelayInterval: 0x18
        case .requestResponseInformation: 0x19
        case .responseInformation: 0x1A
        case .serverReference: 0x1C
        case .reasonString: 0x1F
        case .receiveMaximum: 0x21
        case .topicAliasMaximum: 0x22
        case .topicAlias: 0x23
        case .maximumQoS: 0x24
        case .retainAvailable: 0x25
        case .userProperty: 0x26
        case .maximumPacketSize: 0x27
        case .wildcardSubscriptionAvailable: 0x28
        case .subscriptionIdentifierAvailable: 0x29
        case .sharedSubscriptionAvailable: 0x2A
        }
    }
}
