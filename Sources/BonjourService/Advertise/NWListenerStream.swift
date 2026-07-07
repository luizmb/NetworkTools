// SPDX-License-Identifier: Apache-2.0

#if canImport(Network)
import Foundation
import FP
@preconcurrency import Network
import ReactiveConcurrency

/// A ReactiveConcurrency `Publisher` wrapping `NWListener` for Bonjour service advertising.
///
/// A fresh listener is created on each subscription; advertising stops when the subscription
/// terminates. Emissions are `BonjourListenEvent`; a failure completes the stream.
///
/// Events use platform-agnostic types: `UInt16` for the ready port and
/// ``BonjourConnection`` for accepted connections.
public func bonjourListenerStream(
    serviceType: String,
    serviceName: String? = nil,
    port: NWEndpoint.Port = .any,
    txtRecord: NWTXTRecord = NWTXTRecord(),
    params: NWParameters = .tcp
) -> Publisher<BonjourListenEvent, Error> {
    Publisher { continuation in
        let listener = try NWListener(using: params, on: port)
        listener.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: nil,
            txtRecord: txtRecord
        )
        let delegate = NWListenerStreamDelegate(listener: listener, continuation: continuation)
        delegate.start()
        await continuation.suspendUntilCancelled()
        delegate.stop()
    }
}

/// Variant for when an `NWListener` has already been configured externally.
public func bonjourListenerStream(
    listener: NWListener
) -> Publisher<BonjourListenEvent, Error> {
    Publisher { continuation in
        let delegate = NWListenerStreamDelegate(listener: listener, continuation: continuation)
        delegate.start()
        await continuation.suspendUntilCancelled()
        delegate.stop()
    }
}

private final class NWListenerStreamDelegate: @unchecked Sendable {
    private let listener: NWListener
    private let continuation: Publisher<BonjourListenEvent, Error>.Continuation

    init(listener: NWListener, continuation: Publisher<BonjourListenEvent, Error>.Continuation) {
        self.listener = listener
        self.continuation = continuation

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                continuation.yield(.ready(port: listener.port?.rawValue))
            case let .failed(error): handleError(error)
            case let .waiting(error): handleError(error)
            case .cancelled: continuation.finish()
            case .setup: break
            @unknown default: break
            }
        }

        listener.newConnectionHandler = { [weak self] nwConnection in
            guard self != nil else { return }
            continuation.yield(.newConnection(nwConnection.asBonjourConnection()))
        }

        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard self != nil else { return }
            switch change {
            case .add: continuation.yield(.registered)
            case .remove: continuation.yield(.unregistered)
            @unknown default: break
            }
        }
    }

    func start() { listener.start(queue: .main) }
    func stop() { listener.cancel() }

    private func handleError(_ error: NWError) {
        if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
            continuation.fail(BonjourListenError.permissionDenied)
        } else {
            continuation.fail(BonjourListenError.failed(error: error))
        }
    }
}
#endif
