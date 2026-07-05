import FP
import ReactiveConcurrency

/// A live, full-duplex WebSocket connection with ARC-based lifetime management.
///
/// `WebSocketConnection` is a **class** — the underlying socket stays open exactly
/// as long as at least one reference to this object exists. When the last reference
/// is released, `deinit` sends a normal-closure frame automatically, mirroring how
/// the Combine `WebSocket` closes when its subscription is cancelled.
///
/// Call ``close()`` to close explicitly before the last reference is released.
///
/// The Apple implementation is produced by `URLSession.webSocketConnection(with:)`,
/// which itself returns a `DeferredTask<WebSocketConnection>` so the TCP handshake
/// and WebSocket upgrade remain lazy until the Store runs the task.
///
/// ## Lifecycle
///
/// ```
/// DeferredTask<WebSocketConnection>   ← nothing happens until .run()
///   └─ .run() → TCP + WebSocket upgrade, connection is live
///         └─ hold reference → socket stays open
///               └─ last reference released (deinit) OR close() called → normalClosure
/// ```
///
/// ## Usage
///
/// ```swift
/// let connectionTask = URLSession.shared.webSocketConnection(
///     with: URL(string: "wss://echo.example.com")!
/// )
///
/// // Open the connection — nothing happens before this
/// let conn = await connectionTask.run()
///
/// // Send immediately
/// _ = await conn.send(.text("hello")).run()
///
/// // Receive in a loop — breaks when server or deinit closes the connection
/// for await result in conn.receive {
///     if case .success(.text(let msg)) = result { print("←", msg) }
/// }
/// // Exiting the for-await loop also closes the connection via onTermination.
///
/// // Or close explicitly before releasing the last reference:
/// conn.close()
/// ```
///
/// ## Inside a SwiftRex Behavior
///
/// ```swift
/// let wsBehavior = Behavior<AppAction, AppState, AppEnvironment> { action, _ in
///     guard case .connect(let url) = action else { return .doNothing }
///     return .produce { ctx in
///         Effect.task {
///             let conn = await ctx.environment.openWebSocket(url).run()
///             for await result in conn.receive {
///                 if case .success(let msg) = result { return .messageReceived(msg) }
///             }
///             return .disconnected
///         }
///     }
/// }
/// ```
public final class WebSocketConnection: @unchecked Sendable {
    /// A lazy stream of inbound messages. Iterating starts the receive loop;
    /// terminating the iteration (or `deinit`) closes the connection.
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
        self.cancelAction = cancel
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
