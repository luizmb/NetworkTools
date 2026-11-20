// SPDX-License-Identifier: Apache-2.0

#if canImport(Network)
import Foundation
import FP
import MQTT
@preconcurrency import Network
import ReactiveConcurrency

public extension Listener {
    /// Binds a Network.framework listener (Apple platforms).
    ///
    /// The publisher starts an `NWListener` when subscribed and emits the bound port with the
    /// listener once it is ready. Subscribing to the listener's `accept` emits every connection that
    /// becomes ready; cancelling it cancels the `NWListener`.
    /// - Parameters:
    ///   - port: The port to listen on (`0` lets the system choose).
    ///   - parameters: The listener parameters, e.g. `.tcp`.
    ///   - queue: The queue Network.framework calls back on.
    /// - Returns: A lazy publisher of the bound listener.
    static func nwListener(port: UInt16, parameters: NWParameters, queue: DispatchQueue) -> Publisher<BoundListener, TransportError> {
        .future { () async -> Result<BoundListener, TransportError> in
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                return .failure(.connectionFailed("invalid port \(port)"))
            }
            let created: NWListener
            do {
                created = try NWListener(using: parameters, on: endpointPort)
            } catch {
                return .failure(.connectionFailed(String(describing: error)))
            }
            let box = ListenerBox(created)
            return await box.start(on: queue).map { bound in
                BoundListener(port: Int(bound), listener: Listener { box.accept })
            }
        }
    }
}

/// Holds an `NWListener` and the stream of connections it accepts.
///
/// `@unchecked Sendable`: `NWListener` is documented as thread-safe but not annotated
/// `Sendable`; the only mutable state (`resolved`) is guarded by `lock`.
private final class ListenerBox: @unchecked Sendable {
    let listener: NWListener
    private let accepted: AsyncStream<TransportConnection>
    private let sink: AsyncStream<TransportConnection>.Continuation
    private let lock = NSLock()
    private var resolved = false

    init(_ listener: NWListener) {
        self.listener = listener
        (accepted, sink) = AsyncStream<TransportConnection>.makeStream()
    }

    func start(on queue: DispatchQueue) async -> Result<UInt16, TransportError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<UInt16, TransportError>, Never>) in
            listener.newConnectionHandler = { [sink] connection in
                let box = ConnectionBox(connection)
                box.begin(on: queue) { result in
                    if case .success = result { sink.yield(box.transportConnection) }
                }
            }
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    resolve(continuation, listener.port.map { .success($0.rawValue) } ?? .failure(.connectionFailed("no port")))
                case let .failed(error),
                     let .waiting(error):
                    listener.cancel()
                    resolve(continuation, .failure(.connectionFailed(String(describing: error))))
                case .cancelled:
                    sink.finish()
                    resolve(continuation, .failure(.connectionFailed("cancelled")))
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    var accept: Publisher<TransportConnection, TransportError> {
        Publisher<TransportConnection, TransportError> { continuation async throws(TransportError) in
            await withTaskCancellationHandler {
                for await connection in self.accepted {
                    continuation.yield(connection)
                }
                continuation.finish()
            } onCancel: {
                self.listener.cancel()
            }
        }
    }

    private func resolve(
        _ continuation: CheckedContinuation<Result<UInt16, TransportError>, Never>,
        _ result: Result<UInt16, TransportError>
    ) {
        let first = lock.withLock {
            defer { resolved = true }
            return !resolved
        }
        if first { continuation.resume(returning: result) }
    }
}
#endif
