// SPDX-License-Identifier: Apache-2.0

import MQTT

/// How a broker behaves. MQTT 5 clients are told these limits in CONNACK.
public struct BrokerOptions: Sendable, Hashable {
    /// The largest packet accepted from a client, in bytes.
    public var maximumPacketSize: Int
    /// How many QoS 2 messages a client may have unreleased at once.
    public var receiveMaximum: UInt16
    /// How many topic aliases a client may define.
    public var topicAliasMaximum: UInt16
    /// The highest QoS the broker supports.
    public var maximumQoS: QoS
    /// Whether retained messages are supported.
    public var retainAvailable: Bool
    /// Whether wildcard subscriptions are supported.
    public var wildcardSubscriptionAvailable: Bool
    /// Whether subscription identifiers are supported.
    public var subscriptionIdentifierAvailable: Bool
    /// Whether shared subscriptions (`$share/group/filter`) are supported.
    public var sharedSubscriptionAvailable: Bool
    /// A keep-alive imposed on every client (MQTT 5), if any.
    public var serverKeepAlive: UInt16?
    /// How long a new connection has to send CONNECT.
    public var connectTimeout: Duration
    /// The most QoS 1/2 messages kept for one client while it is offline or busy (oldest dropped first).
    public var maximumQueuedMessages: Int
    /// The prefix of client identifiers the broker assigns (`prefix` + a number).
    public var assignedIdentifierPrefix: String

    /// Creates broker options.
    public init(
        maximumPacketSize: Int = 1 << 20,
        receiveMaximum: UInt16 = 100,
        topicAliasMaximum: UInt16 = 10,
        maximumQoS: QoS = .exactlyOnce,
        retainAvailable: Bool = true,
        wildcardSubscriptionAvailable: Bool = true,
        subscriptionIdentifierAvailable: Bool = true,
        sharedSubscriptionAvailable: Bool = true,
        serverKeepAlive: UInt16? = nil,
        connectTimeout: Duration = .seconds(10),
        maximumQueuedMessages: Int = 1_000,
        assignedIdentifierPrefix: String = "auto-"
    ) {
        self.maximumPacketSize = maximumPacketSize
        self.receiveMaximum = receiveMaximum
        self.topicAliasMaximum = topicAliasMaximum
        self.maximumQoS = maximumQoS
        self.retainAvailable = retainAvailable
        self.wildcardSubscriptionAvailable = wildcardSubscriptionAvailable
        self.subscriptionIdentifierAvailable = subscriptionIdentifierAvailable
        self.sharedSubscriptionAvailable = sharedSubscriptionAvailable
        self.serverKeepAlive = serverKeepAlive
        self.connectTimeout = connectTimeout
        self.maximumQueuedMessages = maximumQueuedMessages
        self.assignedIdentifierPrefix = assignedIdentifierPrefix
    }
}

/// The broker's authentication and authorization decisions: pure functions, injected.
public struct BrokerPolicy: Sendable {
    /// Decides whether a CONNECT is accepted: ``ReasonCode/success`` or a CONNACK failure code
    /// (e.g. ``ReasonCode/badUserNameOrPassword``, ``ReasonCode/notAuthorized``).
    public let authenticate: @Sendable (Connect) -> ReasonCode
    /// Whether a client may publish to a topic.
    public let mayPublish: @Sendable (_ clientIdentifier: String, TopicName) -> Bool
    /// Whether a client may subscribe to a filter.
    public let maySubscribe: @Sendable (_ clientIdentifier: String, TopicFilter) -> Bool

    /// Creates a policy.
    public init(
        authenticate: @escaping @Sendable (Connect) -> ReasonCode,
        mayPublish: @escaping @Sendable (_ clientIdentifier: String, TopicName) -> Bool,
        maySubscribe: @escaping @Sendable (_ clientIdentifier: String, TopicFilter) -> Bool
    ) {
        self.authenticate = authenticate
        self.mayPublish = mayPublish
        self.maySubscribe = maySubscribe
    }

    /// Accepts every client and allows everything except publishing to `$`-topics.
    public static let open = BrokerPolicy(
        authenticate: { _ in .success },
        mayPublish: { _, topic in !topic.rawValue.hasPrefix("$") },
        maySubscribe: { _, _ in true }
    )
}

/// What the broker reports, for logging and monitoring.
public enum BrokerEvent: Sendable, Hashable {
    /// A client connected (`resumed` when an existing session was resumed).
    case clientConnected(clientIdentifier: String, ConnectionID, resumed: Bool)
    /// A connection was refused with this CONNACK reason.
    case clientRefused(ConnectionID, ReasonCode)
    /// A client's connection ended (`graceful` after a DISCONNECT).
    case clientDisconnected(clientIdentifier: String, graceful: Bool)
    /// A client was disconnected because of a protocol error or limit.
    case clientDropped(ConnectionID, ReasonCode)
    /// A message was accepted for distribution.
    case published(Publish, from: String?)
    /// A client's subscriptions changed.
    case subscribed(clientIdentifier: String, [Subscription])
    /// A session expired and was discarded.
    case sessionExpired(clientIdentifier: String)
}

/// Why a broker stopped.
public enum BrokerError: Error, Sendable, Hashable {
    /// The listener failed.
    case listener(TransportError)
    /// A packet could not be encoded.
    case encoding(MQTTEncodingError)
}

/// Something that happens to a broker.
public enum BrokerInput: Sendable, Hashable {
    /// Something happened to a connection, or the clock ticked.
    case connection(ConnectionInput)
    /// The application publishes a message itself (e.g. status topics).
    case publish(Publish)
}

/// What the broker asks the runtime to do.
public typealias BrokerCommand = RuntimeCommand<BrokerEvent, BrokerError>
