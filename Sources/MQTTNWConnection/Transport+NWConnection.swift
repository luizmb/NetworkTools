// SPDX-License-Identifier: Apache-2.0

#if canImport(Network)
import Foundation
import FP
import MQTT
@preconcurrency import Network
import ReactiveConcurrency

public extension Transport {
    /// A transport over Apple's Network.framework.
    ///
    /// Every subscription to ``Transport/connect`` creates and starts a new `NWConnection` and
    /// emits once it is ready. A connection that fails, or that has to wait for a network path
    /// (no route, host unreachable), fails with ``TransportError/connectionFailed(_:)`` instead
    /// of waiting forever.
    ///
    /// ```swift
    /// let transport = Transport.nwConnection(
    ///     host: "10.0.1.49",
    ///     port: 1883,
    ///     parameters: .tcp,
    ///     queue: DispatchQueue(label: "mqtt")
    /// )
    /// ```
    /// - Parameters:
    ///   - host: The broker's host name or IP address.
    ///   - port: The broker's TCP port (1883 for plain MQTT, 8883 for TLS).
    ///   - parameters: The connection parameters, e.g. `.tcp` or `.tls`.
    ///   - queue: The queue Network.framework calls back on.
    /// - Returns: The transport.
    static func nwConnection(host: String, port: UInt16, parameters: NWParameters, queue: DispatchQueue) -> Transport {
        Transport {
            .future { () async -> Result<TransportConnection, TransportError> in
                guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                    return .failure(.connectionFailed("invalid port \(port)"))
                }
                let connection = ConnectionBox(NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters))
                return await connection.start(on: queue).map { connection.transportConnection }
            }
        }
    }
}

/// Holds an `NWConnection` so `@Sendable` closures can capture it, and resolves its readiness once.
///
/// `@unchecked Sendable`: `NWConnection` is documented as thread-safe but not annotated
/// `Sendable`; the only mutable state (`resolved`) is guarded by `lock`.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NWConnection
    private let lock = NSLock()
    private var resolved = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start(on queue: DispatchQueue) async -> Result<Void, TransportError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, TransportError>, Never>) in
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    resolve(continuation, .success(()))
                case let .failed(error), let .waiting(error):
                    connection.cancel()
                    resolve(continuation, .failure(.connectionFailed(String(describing: error))))
                case .cancelled:
                    resolve(continuation, .failure(.connectionFailed("cancelled")))
                case .setup, .preparing:
                    break
                @unknown default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func resolve(_ continuation: CheckedContinuation<Result<Void, TransportError>, Never>, _ result: Result<Void, TransportError>) {
        let first = lock.withLock {
            defer { resolved = true }
            return !resolved
        }
        if first { continuation.resume(returning: result) }
    }

    var transportConnection: TransportConnection {
        TransportConnection(
            receive: Publisher<[UInt8], TransportError> { (continuation) async throws(TransportError) in
                await withTaskCancellationHandler {
                    await self.receiveLoop(continuation)
                } onCancel: {
                    self.connection.cancel()
                }
            },
            send: { bytes in
                .future { () async -> Result<Void, TransportError> in await self.send(bytes) }
            },
            close: {
                Publisher<Void, Never> { (continuation) async throws(Never) in
                    self.connection.cancel()
                    continuation.yield(())
                }
            }
        )
    }

    private func receiveLoop(_ continuation: Publisher<[UInt8], TransportError>.Continuation) async {
        switch await receiveChunk() {
        case let .success((bytes, isComplete)):
            if !bytes.isEmpty { continuation.yield(bytes) }
            guard !isComplete else {
                connection.cancel()
                return continuation.finish()
            }
            await receiveLoop(continuation)
        case let .failure(error):
            continuation.fail(error)
        }
    }

    private func receiveChunk() async -> Result<([UInt8], Bool), TransportError> {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                continuation.resume(returning: error.map { .failure(.connectionLost(String(describing: $0))) }
                    ?? .success((data.map(Array.init) ?? [], isComplete)))
            }
        }
    }

    private func send(_ bytes: [UInt8]) async -> Result<Void, TransportError> {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                continuation.resume(returning: error.map { .failure(.sendFailed(String(describing: $0))) } ?? .success(()))
            })
        }
    }
}
#endif
