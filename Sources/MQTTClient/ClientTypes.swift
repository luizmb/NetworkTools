// SPDX-License-Identifier: Apache-2.0

import MQTT

// An absent password (flag bit off) and an empty one are different things on the wire, so `[UInt8]?` is intended.
// swiftlint:disable discouraged_optional_collection

/// How a client connects.
public struct ClientOptions: Sendable, Hashable {
    /// The protocol version to speak.
    public var version: ProtocolVersion
    /// The client identifier. Empty asks the server to assign one (MQTT 5, or 3.1.1 with `cleanStart`).
    public var clientIdentifier: String
    /// Start a new session instead of resuming the stored one.
    public var cleanStart: Bool
    /// Keep-alive interval in seconds; the client pings this often. `0` disables keep-alive.
    public var keepAlive: UInt16
    /// The message the server publishes if this client disappears.
    public var will: Will?
    /// The user name, if any.
    public var userName: String?
    /// The password, if any.
    public var password: [UInt8]?
    /// CONNECT properties (MQTT 5).
    public var properties: [Property]
    /// The largest packet this client accepts, in bytes.
    public var maximumPacketSize: Int

    /// Creates connection options.
    public init(
        version: ProtocolVersion,
        clientIdentifier: String,
        cleanStart: Bool,
        keepAlive: UInt16,
        will: Will?,
        userName: String?,
        password: [UInt8]?,
        properties: [Property],
        maximumPacketSize: Int
    ) {
        self.version = version
        self.clientIdentifier = clientIdentifier
        self.cleanStart = cleanStart
        self.keepAlive = keepAlive
        self.will = will
        self.userName = userName
        self.password = password
        self.properties = properties
        self.maximumPacketSize = maximumPacketSize
    }

    /// The CONNECT packet these options describe.
    public var connect: Connect {
        Connect(
            protocolVersion: version,
            clientIdentifier: clientIdentifier,
            cleanStart: cleanStart,
            keepAlive: keepAlive,
            will: will,
            userName: userName,
            password: password,
            properties: properties
        )
    }
}

// swiftlint:enable discouraged_optional_collection

/// An application message to publish.
public struct OutgoingMessage: Sendable, Hashable {
    /// Where to publish.
    public var topic: TopicName
    /// The message body.
    public var payload: [UInt8]
    /// The delivery guarantee.
    public var qos: QoS
    /// Whether the server should retain it.
    public var retain: Bool
    /// PUBLISH properties (MQTT 5).
    public var properties: [Property]

    /// Creates a message.
    public init(topic: TopicName, payload: [UInt8], qos: QoS, retain: Bool, properties: [Property]) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retain = retain
        self.properties = properties
    }
}

/// What the application asks the client to do.
public enum ClientRequest: Sendable, Hashable {
    /// Publish a message.
    case publish(OutgoingMessage)
    /// Add subscriptions (with SUBSCRIBE properties).
    case subscribe([Subscription], properties: [Property])
    /// Remove subscriptions (with UNSUBSCRIBE properties).
    case unsubscribe([TopicFilter], properties: [Property])
    /// Send one step of an MQTT 5 extended authentication exchange.
    case authenticate(Auth)
    /// End the session gracefully.
    case disconnect(Disconnect)
}

/// What the client tells the application.
public enum ClientEvent: Sendable, Hashable {
    /// The server accepted the connection.
    case connected(ConnAck)
    /// An application message arrived (delivered once, also for QoS 2).
    case message(Publish)
    /// A QoS 1 or 2 publish finished: PUBACK, or PUBREC with a failure, or PUBCOMP.
    case published(Publish, Acknowledgement)
    /// The server answered a SUBSCRIBE.
    case subscribed([Subscription], SubAck)
    /// The server answered an UNSUBSCRIBE.
    case unsubscribed([TopicFilter], UnsubAck)
    /// The server sent an MQTT 5 AUTH step.
    case authenticationChallenge(Auth)
    /// The session ended: the server sent DISCONNECT, or the application asked to disconnect.
    case disconnected(Disconnect, byServer: Bool)
}

/// Why a client session failed.
public enum ClientError: Error, Sendable, Hashable {
    /// The transport failed.
    case transport(TransportError)
    /// The connection closed while the session was active.
    case connectionClosed
    /// A packet could not be encoded for the session's version.
    case encoding(MQTTEncodingError)
    /// The incoming bytes are not valid MQTT.
    case decoding(PacketStreamError)
    /// The server refused the connection.
    case connectionRefused(ConnAck)
    /// The server broke the protocol.
    case protocolViolation(ProtocolViolation)
    /// No PINGRESP arrived within a keep-alive interval.
    case keepAliveTimeout
    /// All 65 535 packet identifiers are in flight.
    case packetIdentifiersExhausted
}

/// Ways the server can break the protocol, as seen by a client.
public enum ProtocolViolation: Sendable, Hashable {
    /// A packet that is not valid at this point (e.g. anything but CONNACK first, or a
    /// client-to-server packet such as SUBSCRIBE).
    case unexpectedPacket(PacketType)
    /// An acknowledgement for a packet identifier that is not in flight, or not at that stage.
    case unknownPacketIdentifier(PacketType, PacketIdentifier)
}
