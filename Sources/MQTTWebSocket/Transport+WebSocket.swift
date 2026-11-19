// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import MQTT
import ReactiveConcurrency
import WebSocketClient

public extension Transport {
    /// MQTT over WebSocket: each binary frame carries MQTT bytes (a frame may hold part of a
    /// packet or several packets; ``PacketStream`` reassembles them). Text frames are a
    /// protocol error and fail with ``TransportError/unexpectedData(_:)``.
    ///
    /// The WebSocket itself comes from any `WebSocketClient` implementation; the server must be
    /// offered the `mqtt` subprotocol.
    /// - Parameter open: Opens the WebSocket when subscribed.
    /// - Returns: The transport.
    static func webSocket(_ open: @escaping @Sendable () -> Publisher<WebSocketConnection, Never>) -> Transport {
        Transport {
            open().setFailureType(to: TransportError.self).map(webSocketConnection)
        }
    }

    #if canImport(Darwin)
    /// MQTT over WebSocket using `URLSession`, offering the `mqtt` subprotocol.
    ///
    /// ```swift
    /// let transport = Transport.webSocket(url: URL(string: "ws://10.0.1.49:9001/mqtt")!, session: session)
    /// ```
    /// - Parameters:
    ///   - url: The `ws://` or `wss://` endpoint.
    ///   - session: The URL session to open the WebSocket with.
    /// - Returns: The transport.
    static func webSocket(url: URL, session: URLSession) -> Transport {
        webSocket { session.webSocketConnection(with: url, protocols: ["mqtt"]) }
    }
    #endif
}

private func webSocketConnection(_ socket: WebSocketConnection) -> TransportConnection {
    TransportConnection(
        receive: socket.receive
            .mapError { TransportError.connectionLost(String(describing: $0)) }
            .flatMap(maxPublishers: 1, bytes),
        send: { payload in
            socket.send(.data(Data(payload))).mapError { TransportError.sendFailed(String(describing: $0)) }
        },
        close: {
            Publisher<Void, Never> { continuation async throws(Never) in
                socket.close()
                continuation.yield(())
            }
        }
    )
}

private func bytes(_ message: WebSocketMessage) -> Publisher<[UInt8], TransportError> {
    switch message {
    case let .data(data): .just(Array(data))
    case let .text(text): .fail(.unexpectedData(text))
    }
}
