// SPDX-License-Identifier: Apache-2.0

import MQTT

/// Everything a client remembers between two inputs. A plain value: the client is a fold of
/// ``ClientMachine/step(_:)`` over its inputs, starting from ``initial(_:)``.
///
/// It has two parts: the **session** (in-flight messages, subscriptions, packet identifiers,
/// queued requests), which survives reconnects, and the **link** (receive buffer, keep-alive
/// timing, server limits, topic aliases), which belongs to one connection.
public struct ClientState: Sendable, Hashable {
    /// Where the client is in its lifecycle.
    public enum Phase: Sendable, Hashable {
        /// Created, not started.
        case idle
        /// Opening a connection since the given time.
        case connecting(ConnectionID, since: Duration)
        /// Connection open, CONNECT sent at the given time, waiting for CONNACK.
        case awaitingConnAck(ConnectionID, since: Duration)
        /// CONNACK accepted.
        case connected(ConnectionID)
        /// Connection lost; the next attempt is due at the given time.
        case reconnecting(at: Duration)
        /// The session is over.
        case closed
    }

    /// A request waiting for its acknowledgement.
    public enum InFlight: Sendable, Hashable {
        /// QoS 1 publish waiting for PUBACK.
        case awaitingPubAck(Publish)
        /// QoS 2 publish waiting for PUBREC.
        case awaitingPubRec(Publish)
        /// QoS 2 publish released, waiting for PUBCOMP.
        case awaitingPubComp(Publish)
        /// SUBSCRIBE waiting for SUBACK.
        case subscribing([Subscription], properties: [Property])
        /// UNSUBSCRIBE waiting for UNSUBACK.
        case unsubscribing([TopicFilter], properties: [Property])

        var isPublish: Bool {
            switch self {
            case .awaitingPubAck,
                 .awaitingPubRec,
                 .awaitingPubComp: true
            case .subscribing,
                 .unsubscribing: false
            }
        }
    }

    /// One in-flight request, kept in sending order (resends after a reconnect keep that order).
    public struct Entry: Sendable, Hashable {
        /// Its packet identifier.
        public var identifier: PacketIdentifier
        /// What it waits for.
        public var stage: InFlight
    }

    /// Per-connection state, reset on every connection.
    public struct Link: Sendable, Hashable {
        /// Incoming bytes not yet forming a whole packet.
        public var stream: PacketStream
        /// When the last packet was sent.
        public var lastSent: Duration
        /// When the outstanding PINGREQ was sent, if one is outstanding.
        public var pingSentAt: Duration?
        /// What the server announced in CONNACK.
        public var server: ServerLimits
        /// Topic aliases defined by the server for incoming messages.
        public var inboundAliases: [UInt16: TopicName]
        /// Topic aliases this client defined for outgoing messages.
        public var outboundAliases: [TopicName: UInt16]
    }

    /// The options the client was started with.
    public let options: ClientOptions
    /// The lifecycle phase.
    public internal(set) var phase: Phase
    /// The latest clock reading.
    public internal(set) var now: Duration
    /// Consecutive failed connection attempts.
    public internal(set) var failedAttempts: Int
    /// Whether a CONNACK has ever been accepted (re-subscriptions only happen after that).
    public internal(set) var hasConnected: Bool
    /// The number of the next outgoing connection.
    public internal(set) var nextConnection: UInt64
    /// The client identifier to connect with (the server's assigned one once known).
    public internal(set) var clientIdentifier: String
    /// Requests waiting for a connection or for a free Receive Maximum slot, in order.
    public internal(set) var queued: [ClientRequest]
    /// Requests waiting for acknowledgements, in sending order.
    public internal(set) var inFlight: [Entry]
    /// QoS 2 messages received and delivered, waiting for PUBREL (to drop duplicates).
    public internal(set) var receivedQoS2: Set<PacketIdentifier>
    /// The next packet identifier to try.
    public internal(set) var nextIdentifier: PacketIdentifier
    /// Active subscriptions (granted by a SUBACK), renewed after a reconnect without a session.
    public internal(set) var subscriptions: [Subscription]
    /// The current connection's state.
    public internal(set) var link: Link
    /// Where the server redirected the client, if it did.
    public internal(set) var redirect: Redirect?
    /// Redirects followed since the last accepted CONNACK (to stop redirect loops).
    public internal(set) var redirectsFollowed: Int

    /// A server redirect (MQTT 5 Server Reference).
    public struct Redirect: Sendable, Hashable {
        /// The Server Reference.
        public var server: String
        /// `true` for "Server moved" (every later connection), `false` for "Use another server" (the next one).
        public var permanent: Bool
    }

    /// How many redirects are followed in a row before giving up.
    static let maximumRedirects = 5

    /// The state of a client that has not started.
    /// - Parameter options: How to connect.
    /// - Returns: The initial state.
    public static func initial(_ options: ClientOptions) -> ClientState {
        ClientState(
            options: options,
            phase: .idle,
            now: .zero,
            failedAttempts: 0,
            hasConnected: false,
            nextConnection: 1,
            clientIdentifier: options.clientIdentifier,
            queued: [],
            inFlight: [],
            receivedQoS2: [],
            nextIdentifier: .first,
            subscriptions: [],
            link: freshLink(options),
            redirect: nil,
            redirectsFollowed: 0
        )
    }

    static func freshLink(_ options: ClientOptions) -> Link {
        Link(
            stream: PacketStream(version: options.version, maximumPacketSize: options.maximumPacketSize),
            lastSent: .zero,
            pingSentAt: nil,
            server: .defaults,
            inboundAliases: [:],
            outboundAliases: [:]
        )
    }

    /// The connection currently in use, if any.
    var connection: ConnectionID? {
        switch phase {
        case let .connecting(id, _),
             let .awaitingConnAck(id, _),
             let .connected(id): id
        case .idle,
             .reconnecting,
             .closed: nil
        }
    }

    /// QoS 1/2 publishes waiting for their final acknowledgement.
    var inFlightPublishes: Int {
        inFlight.count(where: \.stage.isPublish)
    }

    /// This client's Receive Maximum (from its CONNECT properties).
    var receiveMaximum: Int {
        options.properties.lazy.compactMap { property -> Int? in
            guard case let .receiveMaximum(value) = property else { return nil }
            return Int(value)
        }.first ?? 65_535
    }

    /// This client's Topic Alias Maximum (from its CONNECT properties).
    var topicAliasMaximum: UInt16 {
        options.properties.lazy.compactMap { property -> UInt16? in
            guard case let .topicAliasMaximum(value) = property else { return nil }
            return value
        }.first ?? 0
    }

    /// The keep-alive in force on the current connection, in seconds.
    var keepAlive: UInt16 {
        link.server.serverKeepAlive ?? options.keepAlive
    }
}
