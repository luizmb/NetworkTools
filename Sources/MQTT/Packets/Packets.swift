// SPDX-License-Identifier: Apache-2.0

/// An MQTT control packet, any of the fifteen types, in a version-neutral (MQTT 5-shaped) model.
///
/// The model is a superset: MQTT 3.1.1 packets simply leave properties empty and use the
/// success reason codes. The codec (``Packet/encoder(for:)`` / ``Packet/parser(for:)``) decides
/// what each version can carry and fails with a typed error instead of dropping data.
///
/// Every role uses the same model and codec in both directions: a client encodes CONNECT and
/// decodes CONNACK, a broker does the opposite.
public enum Packet: Sendable, Hashable {
    /// Client → server: open a session.
    case connect(Connect)
    /// Server → client: result of CONNECT.
    case connAck(ConnAck)
    /// Either direction: an application message.
    case publish(Publish)
    /// Acknowledges a QoS 1 PUBLISH.
    case pubAck(Acknowledgement)
    /// QoS 2 step 1: PUBLISH received.
    case pubRec(Acknowledgement)
    /// QoS 2 step 2: release the message.
    case pubRel(Acknowledgement)
    /// QoS 2 step 3: delivery complete.
    case pubComp(Acknowledgement)
    /// Client → server: add subscriptions.
    case subscribe(Subscribe)
    /// Server → client: result of SUBSCRIBE.
    case subAck(SubAck)
    /// Client → server: remove subscriptions.
    case unsubscribe(Unsubscribe)
    /// Server → client: result of UNSUBSCRIBE.
    case unsubAck(UnsubAck)
    /// Client → server: keep-alive probe.
    case pingReq
    /// Server → client: keep-alive answer.
    case pingResp
    /// Either direction: the session is ending.
    case disconnect(Disconnect)
    /// Either direction (MQTT 5 only): extended authentication exchange.
    case auth(Auth)

    /// The control packet type.
    public var type: PacketType {
        switch self {
        case .connect: .connect
        case .connAck: .connAck
        case .publish: .publish
        case .pubAck: .pubAck
        case .pubRec: .pubRec
        case .pubRel: .pubRel
        case .pubComp: .pubComp
        case .subscribe: .subscribe
        case .subAck: .subAck
        case .unsubscribe: .unsubscribe
        case .unsubAck: .unsubAck
        case .pingReq: .pingReq
        case .pingResp: .pingResp
        case .disconnect: .disconnect
        case .auth: .auth
        }
    }
}

// MARK: - CONNECT / CONNACK

/// CONNECT: the first packet a client sends.
public struct Connect: Sendable, Hashable {
    /// The protocol version this CONNECT is written in. It decides how the whole session is encoded.
    public var protocolVersion: ProtocolVersion
    /// The client identifier. May be empty when the server assigns one.
    public var clientIdentifier: String
    /// Start a new session (`true`) or resume an existing one ("Clean Session" in 3.1.1).
    public var cleanStart: Bool
    /// The longest time, in seconds, between two control packets from the client. `0` disables it.
    public var keepAlive: UInt16
    /// The message the server publishes if the client disappears without a DISCONNECT.
    public var will: Will?
    /// The user name, if any.
    public var userName: String?
    /// The password, if any (binary data in the spec).
    public var password: [UInt8]?
    /// CONNECT properties (MQTT 5).
    public var properties: [Property]

    /// Creates a CONNECT packet.
    public init(
        protocolVersion: ProtocolVersion,
        clientIdentifier: String,
        cleanStart: Bool,
        keepAlive: UInt16,
        will: Will?,
        userName: String?,
        password: [UInt8]?,
        properties: [Property]
    ) {
        self.protocolVersion = protocolVersion
        self.clientIdentifier = clientIdentifier
        self.cleanStart = cleanStart
        self.keepAlive = keepAlive
        self.will = will
        self.userName = userName
        self.password = password
        self.properties = properties
    }
}

/// The Will Message carried by CONNECT.
public struct Will: Sendable, Hashable {
    /// Where the will is published.
    public var topic: TopicName
    /// The will's payload.
    public var payload: [UInt8]
    /// The QoS it is published with.
    public var qos: QoS
    /// Whether it is retained.
    public var retain: Bool
    /// Will properties (MQTT 5).
    public var properties: [Property]

    /// Creates a will message.
    public init(topic: TopicName, payload: [UInt8], qos: QoS, retain: Bool, properties: [Property]) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retain = retain
        self.properties = properties
    }
}

/// CONNACK: the server's answer to CONNECT.
public struct ConnAck: Sendable, Hashable {
    /// Whether the server resumed a stored session.
    public var sessionPresent: Bool
    /// The outcome. In 3.1.1 this is the return code mapped to its MQTT 5 equivalent.
    public var reasonCode: ReasonCode
    /// CONNACK properties (MQTT 5).
    public var properties: [Property]

    /// Creates a CONNACK packet.
    public init(sessionPresent: Bool, reasonCode: ReasonCode, properties: [Property]) {
        self.sessionPresent = sessionPresent
        self.reasonCode = reasonCode
        self.properties = properties
    }
}

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
        case let .atLeastOnce(id), let .exactlyOnce(id): id
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

// MARK: - SUBSCRIBE / UNSUBSCRIBE

/// What the server should do with retained messages when a subscription is made (MQTT 5).
public enum RetainHandling: UInt8, Sendable, Hashable, CaseIterable {
    /// Send retained messages on every subscribe (the 3.1.1 behaviour).
    case sendOnSubscribe = 0
    /// Send them only if the subscription did not already exist.
    case sendOnNewSubscription = 1
    /// Never send them.
    case doNotSend = 2
}

/// The options of one subscription.
public struct SubscriptionOptions: Sendable, Hashable {
    /// The maximum QoS the client wants to receive.
    public var qos: QoS
    /// MQTT 5: do not receive messages this client published itself.
    public var noLocal: Bool
    /// MQTT 5: keep the RETAIN flag as published instead of clearing it.
    public var retainAsPublished: Bool
    /// MQTT 5: retained-message policy.
    public var retainHandling: RetainHandling

    /// Creates subscription options.
    public init(qos: QoS, noLocal: Bool, retainAsPublished: Bool, retainHandling: RetainHandling) {
        self.qos = qos
        self.noLocal = noLocal
        self.retainAsPublished = retainAsPublished
        self.retainHandling = retainHandling
    }

    /// Options with only a QoS: the 3.1.1-compatible defaults.
    /// - Parameter qos: The maximum QoS.
    /// - Returns: The options.
    public static func qos(_ qos: QoS) -> SubscriptionOptions {
        SubscriptionOptions(qos: qos, noLocal: false, retainAsPublished: false, retainHandling: .sendOnSubscribe)
    }

    /// `true` when only the QoS is set, i.e. the options are expressible in MQTT 3.1.1.
    var isQoSOnly: Bool {
        !noLocal && !retainAsPublished && retainHandling == .sendOnSubscribe
    }
}

/// One topic filter with its options.
public struct Subscription: Sendable, Hashable {
    /// What to subscribe to.
    public var filter: TopicFilter
    /// How to subscribe.
    public var options: SubscriptionOptions

    /// Creates a subscription.
    public init(filter: TopicFilter, options: SubscriptionOptions) {
        self.filter = filter
        self.options = options
    }
}

/// SUBSCRIBE: add one or more subscriptions.
public struct Subscribe: Sendable, Hashable {
    /// Pairs the request with its SUBACK.
    public var packetIdentifier: PacketIdentifier
    /// The subscriptions; the protocol requires at least one.
    public var subscriptions: [Subscription]
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates a SUBSCRIBE packet.
    public init(packetIdentifier: PacketIdentifier, subscriptions: [Subscription], properties: [Property]) {
        self.packetIdentifier = packetIdentifier
        self.subscriptions = subscriptions
        self.properties = properties
    }
}

/// SUBACK: one reason code per requested subscription, in order.
public struct SubAck: Sendable, Hashable {
    /// The SUBSCRIBE being answered.
    public var packetIdentifier: PacketIdentifier
    /// Granted QoS or failure, per subscription.
    public var reasonCodes: [ReasonCode]
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates a SUBACK packet.
    public init(packetIdentifier: PacketIdentifier, reasonCodes: [ReasonCode], properties: [Property]) {
        self.packetIdentifier = packetIdentifier
        self.reasonCodes = reasonCodes
        self.properties = properties
    }
}

/// UNSUBSCRIBE: remove one or more subscriptions.
public struct Unsubscribe: Sendable, Hashable {
    /// Pairs the request with its UNSUBACK.
    public var packetIdentifier: PacketIdentifier
    /// The filters to remove; the protocol requires at least one.
    public var filters: [TopicFilter]
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates an UNSUBSCRIBE packet.
    public init(packetIdentifier: PacketIdentifier, filters: [TopicFilter], properties: [Property]) {
        self.packetIdentifier = packetIdentifier
        self.filters = filters
        self.properties = properties
    }
}

/// UNSUBACK: the answer to UNSUBSCRIBE.
public struct UnsubAck: Sendable, Hashable {
    /// The UNSUBSCRIBE being answered.
    public var packetIdentifier: PacketIdentifier
    /// MQTT 5: one reason code per filter. Always empty in 3.1.1, which has none.
    public var reasonCodes: [ReasonCode]
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates an UNSUBACK packet.
    public init(packetIdentifier: PacketIdentifier, reasonCodes: [ReasonCode], properties: [Property]) {
        self.packetIdentifier = packetIdentifier
        self.reasonCodes = reasonCodes
        self.properties = properties
    }
}

// MARK: - DISCONNECT / AUTH

/// DISCONNECT: the session is ending.
public struct Disconnect: Sendable, Hashable {
    /// Why (always ``ReasonCode/normalDisconnection`` in 3.1.1).
    public var reasonCode: ReasonCode
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates a DISCONNECT packet.
    public init(reasonCode: ReasonCode, properties: [Property]) {
        self.reasonCode = reasonCode
        self.properties = properties
    }

    /// A normal disconnection with no properties.
    public static let normal = Disconnect(reasonCode: .normalDisconnection, properties: [])
}

/// AUTH (MQTT 5 only): one step of an extended authentication exchange.
public struct Auth: Sendable, Hashable {
    /// The step's outcome.
    public var reasonCode: ReasonCode
    /// Properties, typically Authentication Method and Data.
    public var properties: [Property]

    /// Creates an AUTH packet.
    public init(reasonCode: ReasonCode, properties: [Property]) {
        self.reasonCode = reasonCode
        self.properties = properties
    }
}
