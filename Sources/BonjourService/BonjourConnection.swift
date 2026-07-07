// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import ReactiveConcurrency

/// A live Bonjour (TCP) connection with ARC-based lifetime management.
///
/// `BonjourConnection` is a **class** — the underlying `NWConnection` stays open
/// exactly as long as at least one reference to this object exists. When the last
/// reference is released, `deinit` cancels the connection automatically.
///
/// Call ``close()`` to close explicitly before the last reference is released.
///
/// The Apple implementation is produced inside ``bonjourListenerStream`` when a
/// client connects; a future Linux/NIO implementation would produce the same class
/// from a different factory.
///
/// ## Lifecycle
///
/// ```
/// bonjourListenerStream emits .newConnection(conn)
///   └─ hold reference → NWConnection stays open
///         └─ last reference released (deinit) OR close() called → cancel
/// ```
///
/// ## Usage
///
/// ```swift
/// for await result in bonjourListenerStream(serviceType: "_myapp._tcp.") {
///     if case .success(.newConnection(let conn)) = result {
///         // Read in a background task — conn stays alive as long as this Task runs
///         // consume in your own task:
///             for await dataResult in conn.receive {
///                 if case .success(let data) = dataResult {
///                     print("received \(data.count) bytes")
///                     _ = await conn.send(data).run()   // echo back
///                 }
///             }
///         }
///     }
/// }
/// ```
public final class BonjourConnection: @unchecked Sendable {
    /// A lazy stream of inbound data chunks. Iterating starts reading;
    /// terminating the iteration (or `deinit`) cancels the connection.
    public let receive: Publisher<Data, Error>

    /// Returns a lazy task that, when run, sends one chunk of data.
    ///
    /// ```swift
    /// _ = await conn.send(Data("hello".utf8)).run()
    /// ```
    public let send: @Sendable (Data) -> Publisher<Void, Error>

    private let cancelAction: () -> Void

    public init(
        receive: Publisher<Data, Error>,
        send: @escaping @Sendable (Data) -> Publisher<Void, Error>,
        cancel: @escaping () -> Void
    ) {
        self.receive = receive
        self.send = send
        cancelAction = cancel
    }

    /// Cancels the connection immediately.
    ///
    /// Safe to call multiple times. The connection also cancels automatically
    /// when this object is deallocated.
    public func close() { cancelAction() }

    deinit { cancelAction() }
}
