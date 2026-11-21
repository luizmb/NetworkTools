// SPDX-License-Identifier: Apache-2.0

import MQTT

/// Everything a broker remembers between two inputs: connections, sessions (which outlive
/// connections), retained messages and scheduled wills. A plain value; the broker is a fold of
/// ``BrokerMachine/step(_:)`` over its inputs.
public struct BrokerState: Sendable, Hashable {
    /// A message kept for later delivery, with the time it arrived (for Message Expiry).
    public struct Stored: Sendable, Hashable {
        /// The message as published.
        public var publish: Publish
        /// When the broker received it.
        public var receivedAt: Duration
    }

    /// One network connection.
    public struct Link: Sendable, Hashable {
        /// Where the connection is in its lifecycle.
        public enum Phase: Sendable, Hashable {
            /// Accepted, waiting for CONNECT.
            case awaitingConnect(since: Duration)
            /// CONNECT received; an enhanced authentication exchange is in progress (`round` challenges sent).
            case authenticating(Connect, method: String, round: Int, since: Duration)
            /// CONNECT accepted for this client.
            case connected(clientIdentifier: String)
        }

        /// The lifecycle phase.
        public var phase: Phase
        /// The protocol version (known once CONNECT arrives).
        public var version: ProtocolVersion
        /// Incoming bytes not yet forming a whole packet.
        public var stream: PacketStream
        /// When the last packet arrived (keep-alive).
        public var lastReceived: Duration
        /// The keep-alive in force, in seconds (`0` disables it).
        public var keepAlive: UInt16
        /// The client's Receive Maximum.
        public var clientReceiveMaximum: Int
        /// The client's Maximum Packet Size, if limited.
        public var clientMaximumPacketSize: Int?
        /// Topic aliases the client defined for its publishes.
        public var inboundAliases: [UInt16: TopicName]
        /// The enhanced authentication method the client connected with, if any.
        public var authenticationMethod: String?
        /// Challenges sent in an ongoing re-authentication, if one is in progress.
        public var reauthenticationRound: Int?
    }

    /// One outgoing QoS 1/2 message waiting for acknowledgement.
    public struct Delivery: Sendable, Hashable {
        /// Its packet identifier.
        public var identifier: PacketIdentifier
        /// The PUBLISH as sent.
        public var publish: Publish
        /// `true` once PUBREC arrived (waiting for PUBCOMP).
        public var released: Bool
    }

    /// One subscription inside a session.
    public struct Subscribed: Sendable, Hashable {
        /// Its options.
        public var options: SubscriptionOptions
        /// Its Subscription Identifier, if any.
        public var identifier: UInt32?
    }

    /// A client's session.
    public struct Session: Sendable, Hashable {
        /// The connection currently using it, if any.
        public var connection: ConnectionID?
        /// The client's protocol version.
        public var version: ProtocolVersion
        /// Subscriptions by filter (shared ones keep their full `$share/…` filter).
        public var subscriptions: [TopicFilter: Subscribed]
        /// Outgoing messages waiting for acknowledgement, in order.
        public var inFlight: [Delivery]
        /// Messages waiting for a connection or a free Receive Maximum slot.
        public var queued: [Stored]
        /// Incoming QoS 2 messages already distributed, waiting for PUBREL.
        public var receivedQoS2: Set<PacketIdentifier>
        /// The next packet identifier to try.
        public var nextIdentifier: PacketIdentifier
        /// Session Expiry Interval in seconds (`UInt32.max`: never).
        public var expiry: UInt32
        /// When the client disconnected, if it is offline.
        public var disconnectedAt: Duration?
        /// The client's Will Message, published if it disappears.
        public var will: Will?
    }

    /// A Will Message waiting for its Will Delay Interval.
    public struct ScheduledWill: Sendable, Hashable {
        /// The will.
        public var will: Will
        /// The client it belongs to.
        public var clientIdentifier: String
        /// When to publish it.
        public var at: Duration
    }

    /// The options the broker runs with.
    public let options: BrokerOptions
    /// The latest clock reading.
    public internal(set) var now: Duration
    /// Open connections.
    public internal(set) var links: [ConnectionID: Link]
    /// Sessions by client identifier.
    public internal(set) var sessions: [String: Session]
    /// Retained messages by topic.
    public internal(set) var retained: [TopicName: Stored]
    /// Wills waiting for their delay.
    public internal(set) var wills: [ScheduledWill]
    /// The next number for an assigned client identifier.
    public internal(set) var nextAssigned: UInt64
    /// Round-robin positions of shared subscriptions, by `$share/group/filter`.
    public internal(set) var sharedCursor: [TopicFilter: Int]

    /// A broker with no clients.
    /// - Parameter options: How the broker behaves.
    /// - Returns: The initial state.
    public static func initial(_ options: BrokerOptions) -> BrokerState {
        BrokerState(
            options: options,
            now: .zero,
            links: [:],
            sessions: [:],
            retained: [:],
            wills: [],
            nextAssigned: 1,
            sharedCursor: [:]
        )
    }

    func freshLink() -> Link {
        Link(
            phase: .awaitingConnect(since: now),
            version: .v5,
            stream: PacketStream(version: .v5, maximumPacketSize: options.maximumPacketSize),
            lastReceived: now,
            keepAlive: 0,
            clientReceiveMaximum: 65_535,
            clientMaximumPacketSize: nil,
            inboundAliases: [:],
            authenticationMethod: nil,
            reauthenticationRound: nil
        )
    }

    static func newSession(version: ProtocolVersion, expiry: UInt32, will: Will?, connection: ConnectionID) -> Session {
        Session(
            connection: connection,
            version: version,
            subscriptions: [:],
            inFlight: [],
            queued: [],
            receivedQoS2: [],
            nextIdentifier: .first,
            expiry: expiry,
            disconnectedAt: nil,
            will: will
        )
    }

    /// The client identifier connected on a link, if any.
    func client(on id: ConnectionID) -> String? {
        guard case let .connected(clientIdentifier)? = links[id]?.phase else { return nil }
        return clientIdentifier
    }
}
