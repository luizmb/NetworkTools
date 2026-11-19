// SPDX-License-Identifier: Apache-2.0

// MARK: - CONNECT / CONNACK

// An absent password (flag bit off) and an empty one are different things on the wire, so `[UInt8]?` is intended.
// swiftlint:disable discouraged_optional_collection

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

// swiftlint:enable discouraged_optional_collection
