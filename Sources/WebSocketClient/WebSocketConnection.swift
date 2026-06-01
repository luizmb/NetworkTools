import FP

/// A live, full-duplex WebSocket connection described as pure lazy values.
///
/// `WebSocketConnection` is platform-agnostic: it holds four closures over
/// ``WebSocketMessage`` and `DeferredTask` / ``DeferredStream``, with no reference
/// to any Apple-specific type. The Apple implementation is wired up in
/// `WebSocketConnection+Darwin.swift`; a future Linux/NIO implementation would
/// produce the same struct from a different factory.
///
/// All four operations are **lazy** — nothing runs until the Store (or caller)
/// explicitly executes the task or iterates the stream:
///
/// - ``receive``: iterate to start reading; cancels the underlying transport on termination.
/// - ``send(_:)``: call to obtain a `DeferredTask`; run it to write one message.
/// - ``ping``: run to send a health-check frame and await the response.
/// - ``close``: run to send a normal-closure frame and cancel the transport.
///
/// ## Obtaining a connection
///
/// On Apple platforms, use `URLSession.webSocketConnection(with:)` which itself
/// returns a `DeferredTask<WebSocketConnection>` — the TCP handshake and WebSocket
/// upgrade happen only when the task is run:
///
/// ```swift
/// let connectionTask = URLSession.shared.webSocketConnection(
///     with: URL(string: "wss://echo.example.com")!
/// )
/// // Nothing has happened yet.
///
/// let conn = await connectionTask.run()  // opens the connection
///
/// _ = await conn.send(.text("hello")).run()
///
/// for await result in conn.receive {
///     if case .success(.text(let msg)) = result { print("←", msg) }
/// }
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
///                 if case .success(let msg) = result {
///                     return .messageReceived(msg)
///                 }
///             }
///             return .disconnected
///         }
///     }
/// }
/// ```
public struct WebSocketConnection: Sendable {
    /// A lazy stream of inbound messages. Iterating starts the receive loop;
    /// breaking out of the loop (or the task being cancelled) closes the connection.
    public let receive: DeferredStream<Result<WebSocketMessage, Error>>

    /// Returns a lazy task that, when run, sends one message to the server.
    ///
    /// ```swift
    /// _ = await conn.send(.text("ping")).run()
    /// _ = await conn.send(.data(Data([0x01, 0x02]))).run()
    /// ```
    public let send: @Sendable (WebSocketMessage) -> DeferredTask<Result<Void, Error>>

    /// A lazy task that sends a single ping frame and waits for the pong.
    ///
    /// ```swift
    /// let result = await conn.ping.run()
    /// ```
    public let ping: DeferredTask<Result<Void, Error>>

    /// A lazy task that sends a normal-closure frame and tears down the connection.
    ///
    /// ```swift
    /// await conn.close.run()
    /// ```
    public let close: DeferredTask<Void>

    public init(
        receive: DeferredStream<Result<WebSocketMessage, Error>>,
        send: @escaping @Sendable (WebSocketMessage) -> DeferredTask<Result<Void, Error>>,
        ping: DeferredTask<Result<Void, Error>>,
        close: DeferredTask<Void>
    ) {
        self.receive = receive
        self.send = send
        self.ping = ping
        self.close = close
    }
}
