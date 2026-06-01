#if canImport(Combine)
import Combine
import Core
import Foundation
import Network

extension NWListener {
    /// A Combine publisher that streams events from this listener.
    ///
    /// Shorthand for `NWListenerPublisher(listener: self)`.
    public var publisher: NWListenerPublisher { .init(listener: self) }
}

/// A Combine `Publisher` that advertises a Bonjour service and streams inbound connection events.
///
/// `NWListenerPublisher` wraps `NWListener` into a backpressure-aware Combine stream.
/// Advertising starts lazily — only when the first subscriber signals demand.
///
/// ## Advertising a service and accepting connections
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// let publisher = try NWListenerPublisher(
///     serviceType: "_myapp._tcp.",
///     serviceName: "My Device",
///     port: .any           // OS assigns a port; read it from the .ready event
/// )
///
/// publisher
///     .sink(
///         receiveCompletion: { print("listener stopped:", $0) },
///         receiveValue: { event in
///             switch event {
///             case .ready(let port):
///                 print("advertising on port", port ?? 0)
///             case .newConnection(let connection):
///                 connection.start(queue: .main)
///                 // set up receive / send on `connection`
///             case .serviceRegistrationChanged(let change):
///                 print("registration:", change)
///             }
///         }
///     )
///     .store(in: &cancellables)
/// ```
///
/// ## With an existing NWListener
///
/// ```swift
/// let listener = try NWListener(using: .tcp, on: 8080)
/// listener.service = NWListener.Service(type: "_http._tcp.")
/// listener.publisher
///     .compactMap { if case .newConnection(let c) = $0 { return c } else { return nil } }
///     .sink { connection in handleNewClient(connection) }
///     .store(in: &cancellables)
/// ```
public struct NWListenerPublisher {
    private let listener: NWListener

    /// Use an already-configured `NWListener`. All handlers will be overwritten on subscription.
    public init(listener: NWListener) {
        self.listener = listener
    }

    /// Creates and configures an `NWListener` that advertises a Bonjour service.
    ///
    /// - Parameters:
    ///   - serviceType: Bonjour service type, e.g. `"_myapp._tcp."`.
    ///   - serviceName: Human-readable name; `nil` defaults to the device name.
    ///   - port: Port to listen on; `.any` lets the OS assign one (reported in `.ready`).
    ///   - txtRecord: Optional TXT record metadata advertised alongside the service.
    ///   - params: Network parameters; defaults to plain TCP.
    /// - Throws: `NWError` if the port is already in use or otherwise unavailable.
    public init(
        serviceType: String,
        serviceName: String? = nil,
        port: NWEndpoint.Port = .any,
        txtRecord: NWTXTRecord = NWTXTRecord(),
        params: NWParameters = .tcp
    ) throws {
        let l = try NWListener(using: params, on: port)
        l.service = NWListener.Service(name: serviceName, type: serviceType, domain: nil, txtRecord: txtRecord)
        self.listener = l
    }
}

extension NWListenerPublisher: Publisher {
    public typealias Output = Event
    public typealias Failure = NWListenerError

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(subscriber: subscriber, listener: listener))
    }
}

extension NWListenerPublisher {
    private class Subscription<S: Subscriber>: Combine.Subscription, @unchecked Sendable
    where S.Input == Output, S.Failure == Failure {
        private var buffer: DemandBuffer<S>?
        private let listener: NWListener
        private let lock = NSRecursiveLock()
        private var started = false

        init(subscriber: S, listener: NWListener) {
            self.listener = listener
            self.buffer = DemandBuffer(subscriber: subscriber)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    _ = buffer?.buffer(value: .ready(port: listener.port))
                case let .failed(error):  handleError(error)
                case let .waiting(error): handleError(error)
                case .cancelled:          buffer?.complete(completion: .finished)
                case .setup:              break
                @unknown default:         break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                _ = self?.buffer?.buffer(value: .newConnection(connection))
            }

            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                _ = self?.buffer?.buffer(value: .serviceRegistrationChanged(change))
            }
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }
            lock.lock()
            if !started && demand > .none { started = true; lock.unlock(); start() }
            else { lock.unlock() }
            _ = buffer.demand(demand)
        }

        func cancel() { buffer = nil; started = false; listener.cancel() }
        private func start() { listener.start(queue: .main) }

        private func handleError(_ error: NWError) {
            if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
                buffer?.complete(completion: .failure(.permissionDenied))
            } else {
                buffer?.complete(completion: .failure(.failed(error: error)))
            }
        }
    }
}

// MARK: - Model

extension NWListenerPublisher {
    public enum Event {
        /// The listener is active and advertising via Bonjour. `port` is the OS-assigned
        /// port — always check this when the listener was created with `.any`.
        case ready(port: NWEndpoint.Port?)
        /// A client connected. Call `connection.start(queue:)` to begin I/O.
        case newConnection(NWConnection)
        /// Bonjour service registration status changed (added or removed on the network).
        case serviceRegistrationChanged(NWListener.ServiceRegistrationChange)
    }

    public enum NWListenerError: Error {
        /// Local network access was denied by the OS or user.
        case permissionDenied
        /// The listener failed with an underlying network error.
        case failed(error: NWError)
    }
}
#endif
