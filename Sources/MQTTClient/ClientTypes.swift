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
    /// Start a new session on every connection instead of resuming the stored one.
    public var cleanStart: Bool
    /// Keep-alive interval in seconds (`0` disables it). An MQTT 5 server may override it.
    public var keepAlive: UInt16
    /// The message the server publishes if this client disappears.
    public var will: Will?
    /// The user name, if any.
    public var userName: String?
    /// The password, if any.
    public var password: [UInt8]?
    /// CONNECT properties (MQTT 5). `receiveMaximum` and `topicAliasMaximum` set here are
    /// enforced on incoming traffic; `maximumPacketSize` is added from ``maximumPacketSize``
    /// when absent.
    public var properties: [Property]
    /// The largest packet this client accepts, in bytes.
    public var maximumPacketSize: Int
    /// How long opening a connection and receiving CONNACK may take.
    public var connectTimeout: Duration
    /// Whether and when to reconnect after losing the connection.
    public var reconnect: ReconnectPolicy

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
        maximumPacketSize: Int,
        connectTimeout: Duration = .seconds(10),
        reconnect: ReconnectPolicy = .never
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
        self.connectTimeout = connectTimeout
        self.reconnect = reconnect
    }
}

// swiftlint:enable discouraged_optional_collection

/// When a client reconnects after losing its connection.
public enum ReconnectPolicy: Sendable, Hashable {
    /// Never: losing the connection ends the session with a failure.
    case never
    /// Wait `initial`, then double the wait after every failed attempt up to `maximum`; give up
    /// after `attempts` consecutive failures (`nil` retries forever).
    case exponentialBackoff(initial: Duration, maximum: Duration, attempts: Int?)

    /// The wait before reconnect attempt number `attempt` (1-based), or `nil` to give up.
    /// - Parameter attempt: The attempt about to be made.
    /// - Returns: The delay, or `nil`.
    public func delay(beforeAttempt attempt: Int) -> Duration? {
        switch self {
        case .never:
            nil
        case let .exponentialBackoff(initial, maximum, attempts):
            attempts.map { attempt > $0 } ?? false
                ? nil
                : min(maximum, initial * (1 << min(attempt - 1, 30)))
        }
    }
}

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

/// Why the client refused a request instead of sending it.
public enum RequestRejection: Sendable, Hashable {
    /// The server's Maximum QoS is lower than the message's.
    case qosNotSupported(maximum: QoS)
    /// The server does not support retained messages.
    case retainNotSupported
    /// The server does not support wildcard subscriptions.
    case wildcardSubscriptionsNotSupported
    /// The server does not support shared subscriptions.
    case sharedSubscriptionsNotSupported
    /// The server does not support subscription identifiers.
    case subscriptionIdentifiersNotSupported
    /// The packet would exceed the server's Maximum Packet Size.
    case packetTooLarge(size: Int, maximum: Int)
    /// The packet cannot be encoded for the session's version.
    case encoding(MQTTEncodingError)
}

/// What the client tells the application.
public enum ClientEvent: Sendable, Hashable {
    /// The server accepted the connection (on every connect and reconnect).
    case connected(ConnAck)
    /// An application message arrived (delivered once, also for QoS 2). Topic aliases are resolved.
    case message(Publish)
    /// A QoS 1 or 2 publish finished: PUBACK, a failed PUBREC, or PUBCOMP.
    case published(Publish, Acknowledgement)
    /// The server answered a SUBSCRIBE (including automatic re-subscriptions after a reconnect).
    case subscribed([Subscription], SubAck)
    /// The server answered an UNSUBSCRIBE.
    case unsubscribed([TopicFilter], UnsubAck)
    /// A request was refused before sending, because the server cannot accept it.
    case rejected(ClientRequest, RequestRejection)
    /// The server sent an MQTT 5 AUTH step.
    case authenticationChallenge(Auth)
    /// The connection was lost; the client reconnects after the given delay.
    case connectionLost(ClientError, retryingIn: Duration)
    /// The server sent DISCONNECT, or the application asked to disconnect.
    case disconnected(Disconnect, byServer: Bool)
}

/// Why a client session failed.
public enum ClientError: Error, Sendable, Hashable {
    /// The transport failed.
    case transport(TransportError)
    /// The connection closed while the session was active.
    case connectionClosed
    /// Opening the connection and receiving CONNACK took longer than ``ClientOptions/connectTimeout``.
    case connectTimeout
    /// A packet could not be encoded for the session's version.
    case encoding(MQTTEncodingError)
    /// The incoming bytes are not valid MQTT.
    case decoding(PacketStreamError)
    /// The server refused the connection.
    case connectionRefused(ConnAck)
    /// The server ended the connection with a DISCONNECT.
    case disconnectedByServer(Disconnect)
    /// The server broke the protocol.
    case protocolViolation(ProtocolViolation)
    /// No PINGRESP arrived within a keep-alive interval.
    case keepAliveTimeout
    /// All 65 535 packet identifiers are in flight.
    case packetIdentifiersExhausted
}

/// Ways the server can break the protocol, as seen by a client.
public enum ProtocolViolation: Error, Sendable, Hashable {
    /// A packet that is not valid at this point (e.g. anything but CONNACK first, or a
    /// client-to-server packet such as SUBSCRIBE).
    case unexpectedPacket(PacketType)
    /// An acknowledgement for a packet identifier that is not in flight, or not at that stage.
    case unknownPacketIdentifier(PacketType, PacketIdentifier)
    /// A Topic Alias of 0, above this client's Topic Alias Maximum, or never defined.
    case topicAliasInvalid(UInt16)
    /// A PUBLISH with neither a topic name nor a Topic Alias.
    case missingTopic
    /// More unacknowledged QoS 2 messages than this client's Receive Maximum.
    case receiveMaximumExceeded
}

/// The limits an MQTT 5 server announces in CONNACK (MQTT 3.1.1 servers get the defaults).
public struct ServerLimits: Sendable, Hashable {
    /// How many QoS 1/2 publishes may be unacknowledged at once.
    public var receiveMaximum: Int
    /// The largest packet the server accepts, if limited.
    public var maximumPacketSize: Int?
    /// How many topic aliases the client may define.
    public var topicAliasMaximum: UInt16
    /// The highest QoS the server supports.
    public var maximumQoS: QoS
    /// Whether retained messages are supported.
    public var retainAvailable: Bool
    /// Whether wildcard subscriptions are supported.
    public var wildcardSubscriptionAvailable: Bool
    /// Whether subscription identifiers are supported.
    public var subscriptionIdentifierAvailable: Bool
    /// Whether shared subscriptions are supported.
    public var sharedSubscriptionAvailable: Bool
    /// The keep-alive the server imposes, if any.
    public var serverKeepAlive: UInt16?
    /// The client identifier the server assigned, if any.
    public var assignedClientIdentifier: String?

    /// The values that apply when the server announces nothing.
    public static let defaults = ServerLimits(
        receiveMaximum: 65_535,
        maximumPacketSize: nil,
        topicAliasMaximum: 0,
        maximumQoS: .exactlyOnce,
        retainAvailable: true,
        wildcardSubscriptionAvailable: true,
        subscriptionIdentifierAvailable: true,
        sharedSubscriptionAvailable: true,
        serverKeepAlive: nil,
        assignedClientIdentifier: nil
    )

    /// Reads the limits from CONNACK properties.
    /// - Parameter properties: The CONNACK properties.
    /// - Returns: The limits, defaults where a property is absent.
    public static func from(_ properties: [Property]) -> ServerLimits {
        properties.reduce(into: defaults) { limits, property in
            switch property {
            case let .receiveMaximum(value): limits.receiveMaximum = Int(value)
            case let .maximumPacketSize(value): limits.maximumPacketSize = Int(value)
            case let .topicAliasMaximum(value): limits.topicAliasMaximum = value
            case let .maximumQoS(value): limits.maximumQoS = QoS(rawValue: value) ?? .exactlyOnce
            case let .retainAvailable(value): limits.retainAvailable = value != 0
            case let .wildcardSubscriptionAvailable(value): limits.wildcardSubscriptionAvailable = value != 0
            case let .subscriptionIdentifierAvailable(value): limits.subscriptionIdentifierAvailable = value != 0
            case let .sharedSubscriptionAvailable(value): limits.sharedSubscriptionAvailable = value != 0
            case let .serverKeepAlive(value): limits.serverKeepAlive = value
            case let .assignedClientIdentifier(value): limits.assignedClientIdentifier = value
            default: break
            }
        }
    }
}
