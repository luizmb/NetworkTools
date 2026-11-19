// SPDX-License-Identifier: Apache-2.0

import MQTT

/// Everything a client session remembers between two inputs. A plain value: the session is a
/// fold of ``ClientMachine/step(_:)`` over its inputs, starting from ``initial(_:)``.
public struct ClientState: Sendable, Hashable {
    /// Where the session is in its lifecycle.
    public enum Phase: Sendable, Hashable {
        /// Created, CONNECT not yet sent.
        case idle
        /// CONNECT sent, waiting for CONNACK.
        case connecting
        /// CONNACK accepted.
        case connected
        /// The session is over; the transport is being closed.
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
        case subscribing([Subscription])
        /// UNSUBSCRIBE waiting for UNSUBACK.
        case unsubscribing([TopicFilter])
    }

    /// The options the session was started with.
    public let options: ClientOptions
    /// The lifecycle phase.
    public internal(set) var phase: Phase
    /// Requests made before CONNACK, sent once connected.
    public internal(set) var queued: [ClientRequest]
    /// Requests waiting for acknowledgements, by packet identifier.
    public internal(set) var inFlight: [PacketIdentifier: InFlight]
    /// QoS 2 messages received and delivered, waiting for PUBREL (to drop duplicates).
    public internal(set) var receivedQoS2: Set<PacketIdentifier>
    /// The next packet identifier to try.
    public internal(set) var nextIdentifier: PacketIdentifier
    /// Whether a PINGREQ is waiting for its PINGRESP.
    public internal(set) var pingOutstanding: Bool
    /// Incoming bytes not yet forming a whole packet.
    public internal(set) var stream: PacketStream

    /// The state of a session that has not started yet.
    /// - Parameter options: How to connect.
    /// - Returns: The initial state.
    public static func initial(_ options: ClientOptions) -> ClientState {
        ClientState(
            options: options,
            phase: .idle,
            queued: [],
            inFlight: [:],
            receivedQoS2: [],
            nextIdentifier: .first,
            pingOutstanding: false,
            stream: PacketStream(version: options.version, maximumPacketSize: options.maximumPacketSize)
        )
    }
}
