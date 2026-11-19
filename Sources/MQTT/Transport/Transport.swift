// SPDX-License-Identifier: Apache-2.0

import ReactiveConcurrency

/// A way to open a byte connection to an MQTT peer: the protocol witness every transport
/// implements (`MQTTNWConnection`, `MQTTNIO`, `MQTTWebSocket`, or a test double).
///
/// The MQTT core never opens sockets itself. A transport value is fully configured (host, port,
/// TLS, event loop, URL, …) when it is built, so connecting is a plain lazy effect: nothing
/// happens until the returned publisher is subscribed, and every subscription opens a new
/// connection.
///
/// ```swift
/// let transport = Transport { .just(TransportConnection(receive: ..., send: ..., close: ...)) }
/// ```
public struct Transport: Sendable {
    /// Opens a connection. Emits one ``TransportConnection`` and finishes, or fails.
    public let connect: @Sendable () -> Publisher<TransportConnection, TransportError>

    /// Creates a transport from its connect effect.
    /// - Parameter connect: Opens a connection when subscribed.
    public init(connect: @escaping @Sendable () -> Publisher<TransportConnection, TransportError>) {
        self.connect = connect
    }
}

/// An open, full-duplex byte connection.
///
/// Bytes arrive in arbitrary chunks — ``PacketStream`` reassembles packets from them.
public struct TransportConnection: Sendable {
    /// Inbound bytes. Subscribe once. Finishes when the peer closes the connection; fails when
    /// the connection breaks.
    public let receive: Publisher<[UInt8], TransportError>
    /// Writes bytes. Completes (emitting `()`) once they are handed to the network.
    public let send: @Sendable ([UInt8]) -> Publisher<Void, TransportError>
    /// Closes the connection. Idempotent.
    public let close: @Sendable () -> Publisher<Void, Never>

    /// Creates a connection from its three effects.
    /// - Parameters:
    ///   - receive: Inbound bytes.
    ///   - send: Writes bytes.
    ///   - close: Closes the connection.
    public init(
        receive: Publisher<[UInt8], TransportError>,
        send: @escaping @Sendable ([UInt8]) -> Publisher<Void, TransportError>,
        close: @escaping @Sendable () -> Publisher<Void, Never>
    ) {
        self.receive = receive
        self.send = send
        self.close = close
    }
}

/// Why a transport could not deliver bytes.
///
/// Each implementation reports its native error (an `NWError`, a NIO error, a URLSession error)
/// as a description, so this type stays the same whichever transport is used.
public enum TransportError: Error, Sendable, Hashable {
    /// The connection could not be opened.
    case connectionFailed(String)
    /// The open connection broke.
    case connectionLost(String)
    /// Bytes could not be written.
    case sendFailed(String)
    /// The peer sent something the transport cannot carry (e.g. a WebSocket text frame).
    case unexpectedData(String)
}
