#if canImport(Network)
import Foundation
import FP
@preconcurrency import Network

/// Native ``DeferredStream`` wrapping `NWListener` for Bonjour service advertising.
///
/// A fresh listener is created on each iteration; advertising stops when the iterator
/// terminates. Emissions are `Result<BonjourListenEvent, Error>`.
///
/// Events use platform-agnostic types: `UInt16` for the ready port and
/// ``BonjourConnection`` for accepted connections.
///
/// This implementation does not depend on Combine.
///
/// ## Example
///
/// ```swift
/// for await result in bonjourListenerStream(serviceType: "_myapp._tcp.", serviceName: "My Device") {
///     switch result {
///     case .success(.ready(let port)):
///         print("advertising on port", port ?? 0)
///     case .success(.newConnection(let conn)):
///         Task {
///             for await dataResult in conn.receive {
///                 if case .success(let data) = dataResult { handle(data) }
///             }
///         }
///         _ = await conn.send(Data("hello".utf8)).run()
///     case .success(.registered):
///         print("Bonjour registration confirmed")
///     case .failure(let err):
///         print("listener error:", err)
///     }
/// }
/// ```
public func bonjourListenerStream(
    serviceType: String,
    serviceName: String? = nil,
    port: NWEndpoint.Port = .any,
    txtRecord: NWTXTRecord = NWTXTRecord(),
    params: NWParameters = .tcp
) -> DeferredStream<Result<BonjourListenEvent, Error>> {
    DeferredStream {
        AsyncStream { continuation in
            do {
                let listener = try NWListener(using: params, on: port)
                listener.service = NWListener.Service(
                    name: serviceName,
                    type: serviceType,
                    domain: nil,
                    txtRecord: txtRecord
                )
                let delegate = NWListenerStreamDelegate(listener: listener, continuation: continuation)
                continuation.onTermination = { @Sendable _ in delegate.stop() }
                delegate.start()
            } catch {
                continuation.yield(.failure(error))
                continuation.finish()
            }
        }
    }
}

/// Variant for when an `NWListener` has already been configured externally.
public func bonjourListenerStream(
    listener: NWListener
) -> DeferredStream<Result<BonjourListenEvent, Error>> {
    DeferredStream {
        AsyncStream { continuation in
            let delegate = NWListenerStreamDelegate(listener: listener, continuation: continuation)
            continuation.onTermination = { @Sendable _ in delegate.stop() }
            delegate.start()
        }
    }
}

private final class NWListenerStreamDelegate: @unchecked Sendable {
    private let listener: NWListener
    private let continuation: AsyncStream<Result<BonjourListenEvent, Error>>.Continuation

    init(listener: NWListener, continuation: AsyncStream<Result<BonjourListenEvent, Error>>.Continuation) {
        self.listener = listener
        self.continuation = continuation

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                continuation.yield(.success(.ready(port: listener.port?.rawValue)))
            case let .failed(error):  handleError(error)
            case let .waiting(error): handleError(error)
            case .cancelled:          continuation.finish()
            case .setup:              break
            @unknown default:         break
            }
        }

        listener.newConnectionHandler = { [weak self] nwConnection in
            guard let self else { return }
            let conn = nwConnection.asBonjourConnection()
            continuation.yield(.success(.newConnection(conn)))
        }

        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            switch change {
            case .add:    continuation.yield(.success(.registered))
            case .remove: continuation.yield(.success(.unregistered))
            @unknown default: break
            }
        }
    }

    func start() { listener.start(queue: .main) }
    func stop()  { listener.cancel() }

    private func handleError(_ error: NWError) {
        if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
            continuation.yield(.failure(BonjourListenError.permissionDenied))
        } else {
            continuation.yield(.failure(BonjourListenError.failed(error: error)))
        }
        continuation.finish()
    }
}
#endif
