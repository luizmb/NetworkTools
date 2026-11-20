// SPDX-License-Identifier: Apache-2.0

import ReactiveConcurrency

/// A `Transport` and a `Listener` joined in memory: every connection opened by ``transport`` is
/// accepted by ``listener``, and bytes travel between the two ends without a socket.
///
/// Use it to run a client or a bridge in the same process as an `MQTTBroker` (merge ``listener``
/// with the broker's network listeners using ``Listener/merge(_:)``), or to test protocols without
/// a network.
///
/// ```swift
/// let link = InMemoryLink.make()
/// let brokerWorld = BrokerWorld(listener: .merge([tcpListener, link.listener]), clock: clock)
/// let clientWorld = ClientWorld(transport: link.transport, clock: clock)
/// ```
///
/// Create the link at the application's boundary, like any other resource: both ends share it.
public struct InMemoryLink: Sendable {
    /// Opens connections to ``listener``.
    public let transport: Transport
    /// Accepts the connections opened through ``transport``. Subscribe once.
    public let listener: Listener

    /// Creates a connected transport/listener pair.
    /// - Returns: The link.
    public static func make() -> InMemoryLink {
        let (accepted, acceptor) = AsyncStream<TransportConnection>.makeStream()
        let transport = Transport {
            .future { () async -> Result<TransportConnection, TransportError> in
                let (toServer, serverSink) = AsyncStream<[UInt8]>.makeStream()
                let (toClient, clientSink) = AsyncStream<[UInt8]>.makeStream()
                let hangUp: @Sendable () -> Void = {
                    serverSink.finish()
                    clientSink.finish()
                }
                acceptor.yield(end(receiving: toServer, sending: clientSink, hangUp: hangUp))
                return .success(end(receiving: toClient, sending: serverSink, hangUp: hangUp))
            }
        }
        let listener = Listener {
            Publisher<TransportConnection, TransportError> { continuation async throws(TransportError) in
                for await connection in accepted {
                    continuation.yield(connection)
                }
                continuation.finish()
            }
        }
        return InMemoryLink(transport: transport, listener: listener)
    }
}

/// One end of an in-memory connection. Cancelling `receive` or calling `close` hangs up both ends.
private func end(
    receiving inbound: AsyncStream<[UInt8]>,
    sending outbound: AsyncStream<[UInt8]>.Continuation,
    hangUp: @escaping @Sendable () -> Void
) -> TransportConnection {
    TransportConnection(
        receive: Publisher<[UInt8], TransportError> { continuation async throws(TransportError) in
            await withTaskCancellationHandler {
                for await bytes in inbound {
                    continuation.yield(bytes)
                }
                continuation.finish()
            } onCancel: {
                hangUp()
            }
        },
        send: { bytes in
            .future { () async -> Result<Void, TransportError> in
                switch outbound.yield(bytes) {
                case .enqueued: .success(())
                case .dropped,
                     .terminated: .failure(.sendFailed("the other end hung up"))
                @unknown default: .failure(.sendFailed("the other end hung up"))
                }
            }
        },
        close: {
            Publisher<Void, Never> { continuation async throws(Never) in
                hangUp()
                continuation.yield(())
            }
        }
    )
}

public extension Listener {
    /// Accepts connections from every listener at once (e.g. TCP, WebSocket and an in-memory link).
    /// - Parameter listeners: The listeners to merge.
    /// - Returns: A listener emitting every connection any of them accepts.
    static func merge(_ listeners: [Listener]) -> Listener {
        Listener { .merge(listeners.map { $0.accept() }) }
    }
}
