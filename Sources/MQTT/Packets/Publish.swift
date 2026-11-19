// SPDX-License-Identifier: Apache-2.0

// MARK: - PUBLISH and its acknowledgements

/// How a PUBLISH is delivered. QoS 1 and 2 carry the packet identifier that pairs the message
/// with its acknowledgements, so a QoS > 0 publish without an identifier cannot be built.
public enum Delivery: Sendable, Hashable {
    /// QoS 0.
    case atMostOnce
    /// QoS 1, acknowledged by PUBACK.
    case atLeastOnce(PacketIdentifier)
    /// QoS 2, acknowledged by PUBREC / PUBREL / PUBCOMP.
    case exactlyOnce(PacketIdentifier)

    /// The QoS level of this delivery.
    public var qos: QoS {
        switch self {
        case .atMostOnce: .atMostOnce
        case .atLeastOnce: .atLeastOnce
        case .exactlyOnce: .exactlyOnce
        }
    }

    /// The packet identifier, for QoS 1 and 2.
    public var packetIdentifier: PacketIdentifier? {
        switch self {
        case .atMostOnce: nil
        case let .atLeastOnce(id),
             let .exactlyOnce(id): id
        }
    }

    /// Builds the delivery for `qos`, using `identifier` when the QoS needs one.
    /// - Parameters:
    ///   - qos: The QoS level.
    ///   - identifier: The packet identifier for QoS 1 and 2.
    /// - Returns: The delivery.
    public static func make(_ qos: QoS, identifier: PacketIdentifier) -> Delivery {
        switch qos {
        case .atMostOnce: .atMostOnce
        case .atLeastOnce: .atLeastOnce(identifier)
        case .exactlyOnce: .exactlyOnce(identifier)
        }
    }
}

/// PUBLISH: an application message.
public struct Publish: Sendable, Hashable {
    /// The topic. Empty only when an MQTT 5 Topic Alias property stands in for it.
    public var topic: TopicName
    /// The message body.
    public var payload: [UInt8]
    /// QoS and packet identifier.
    public var delivery: Delivery
    /// Whether the server should keep it as the topic's retained message.
    public var retain: Bool
    /// Set on re-deliveries of a QoS 1/2 message.
    public var duplicate: Bool
    /// PUBLISH properties (MQTT 5).
    public var properties: [Property]

    /// Creates a PUBLISH packet.
    public init(
        topic: TopicName,
        payload: [UInt8],
        delivery: Delivery,
        retain: Bool,
        duplicate: Bool,
        properties: [Property]
    ) {
        self.topic = topic
        self.payload = payload
        self.delivery = delivery
        self.retain = retain
        self.duplicate = duplicate
        self.properties = properties
    }
}

/// The common shape of PUBACK, PUBREC, PUBREL and PUBCOMP.
public struct Acknowledgement: Sendable, Hashable {
    /// The identifier of the PUBLISH being acknowledged.
    public var packetIdentifier: PacketIdentifier
    /// The outcome (always ``ReasonCode/success`` in 3.1.1).
    public var reasonCode: ReasonCode
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates an acknowledgement.
    public init(packetIdentifier: PacketIdentifier, reasonCode: ReasonCode, properties: [Property]) {
        self.packetIdentifier = packetIdentifier
        self.reasonCode = reasonCode
        self.properties = properties
    }

    /// A successful acknowledgement with no properties.
    /// - Parameter packetIdentifier: The identifier being acknowledged.
    /// - Returns: The acknowledgement.
    public static func success(_ packetIdentifier: PacketIdentifier) -> Acknowledgement {
        Acknowledgement(packetIdentifier: packetIdentifier, reasonCode: .success, properties: [])
    }
}
