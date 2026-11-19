// SPDX-License-Identifier: Apache-2.0

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
