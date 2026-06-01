import Foundation
import FP

/// A platform-agnostic Bonjour (TCP) connection described as pure lazy values.
///
/// `BonjourConnection` mirrors the shape of `WebSocketConnection` for raw TCP streams
/// accepted via ``bonjourListenerStream``. It holds three closures over `Data`,
/// `DeferredTask`, and `DeferredStream`, with no reference to `NWConnection` or any
/// other Apple-specific type.
///
/// The Apple implementation is wired up in `BonjourConnection+Darwin.swift`;
/// a future Linux/NIO implementation would produce the same struct from a
/// different factory.
///
/// All operations are **lazy** — nothing runs until explicitly executed:
///
/// - ``receive``: iterate to start reading; terminates when the remote end closes.
/// - ``send(_:)``: call to get a `DeferredTask`; run it to write one chunk.
/// - ``close``: run to cancel the connection.
///
/// ## Usage
///
/// ```swift
/// for await result in bonjourListenerStream(serviceType: "_myapp._tcp.") {
///     if case .success(.newConnection(let conn)) = result {
///         // Read incoming data
///         Task {
///             for await dataResult in conn.receive {
///                 if case .success(let data) = dataResult {
///                     print("received \(data.count) bytes")
///                 }
///             }
///         }
///         // Send a response
///         _ = await conn.send(Data("hello".utf8)).run()
///     }
/// }
/// ```
public struct BonjourConnection: Sendable {
    /// A lazy stream of inbound data chunks. Iterate to start receiving;
    /// stream completes when the remote end closes the connection.
    public let receive: DeferredStream<Result<Data, Error>>

    /// Returns a lazy task that, when run, sends one chunk of data.
    ///
    /// ```swift
    /// _ = await conn.send(Data("hello".utf8)).run()
    /// ```
    public let send: @Sendable (Data) -> DeferredTask<Result<Void, Error>>

    /// A lazy task that cancels the connection immediately.
    public let close: DeferredTask<Void>

    public init(
        receive: DeferredStream<Result<Data, Error>>,
        send: @escaping @Sendable (Data) -> DeferredTask<Result<Void, Error>>,
        close: DeferredTask<Void>
    ) {
        self.receive = receive
        self.send = send
        self.close = close
    }
}
