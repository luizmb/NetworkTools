// SPDX-License-Identifier: Apache-2.0

import FP
import ReactiveConcurrency

/// A live, full-duplex WebSocket connection with ARC-based lifetime management.
///
/// `WebSocketConnection` is a **class** — the underlying socket stays open exactly
/// as long as at least one reference to this object exists. When the last reference
/// is released, `deinit` sends a normal-closure frame automatically.
///
/// Call ``close()`` to close explicitly before the last reference is released.
///
/// The Apple implementation is produced by `URLSession.webSocketConnection(with:)`,
/// which returns a `Publisher<WebSocketConnection, Never>` so the TCP handshake and
/// WebSocket upgrade remain lazy until the publisher is subscribed.
///
/// ## Usage
///
/// ```swift
/// let conn = await URLSession.shared
///     .webSocketConnection(with: URL(string: "wss://echo.example.com")!)
///     .firstResultTask().run()
///
/// // Send immediately
/// _ = await conn.send(.text("hello")).firstResultTask().run()
///
/// // Receive in a loop — ends when the server or deinit closes the connection
/// for await result in conn.receive.values {
///     if case .success(.text(let msg)) = result { print("←", msg) }
/// }
/// // Ending the loop also closes the connection.
///
/// // Or close explicitly before releasing the last reference:
/// conn.close()
/// ```
public final class WebSocketConnection: @unchecked Sendable {
    /// A lazy `Publisher` of inbound messages. Subscribing starts the receive loop;
    /// terminating the subscription (or `deinit`) closes the connection.
    public let receive: Publisher<WebSocketMessage, Error>

    /// Returns a lazy task that, when run, sends one message to the server.
    ///
    /// ```swift
    /// _ = await conn.send(.text("ping")).run()
    /// _ = await conn.send(.data(Data([0x01]))).run()
    /// ```
    public let send: @Sendable (WebSocketMessage) -> Publisher<Void, Error>

    /// A lazy task that sends a single ping frame and waits for the pong.
    ///
    /// ```swift
    /// let result = await conn.ping.run()
    /// ```
    public let ping: Publisher<Void, Error>

    private let cancelAction: () -> Void

    public init(
        receive: Publisher<WebSocketMessage, Error>,
        send: @escaping @Sendable (WebSocketMessage) -> Publisher<Void, Error>,
        ping: Publisher<Void, Error>,
        cancel: @escaping () -> Void
    ) {
        self.receive = receive
        self.send = send
        self.ping = ping
        cancelAction = cancel
    }

    /// Closes the connection immediately with a normal-closure frame.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops on the underlying task.
    /// The connection also closes automatically when this object is deallocated, so
    /// explicit `close()` is only needed when you want to close before releasing the
    /// last reference.
    public func close() { cancelAction() }

    deinit { cancelAction() }
}
