#if canImport(Combine)
import Combine
import Core
import Foundation

extension NetService {
    /// Returns a publisher that resolves this service and optionally monitors its TXT record.
    ///
    /// ```swift
    /// NetService(domain: "local.", type: "_http._tcp.", name: "My Server")
    ///     .publisher(monitorDevice: .doNotMonitorTXTUpdates, timeout: 5)
    ///     .sink(
    ///         receiveCompletion: { _ in },
    ///         receiveValue: { event in
    ///             if case .didResolveAddress = event.type {
    ///                 print("IPs:", event.netService.parsedAddresses())
    ///             }
    ///         }
    ///     )
    ///     .store(in: &cancellables)
    /// ```
    public func publisher(
        monitorDevice strategy: NetServiceTXTRecordsMonitorStrategy,
        timeout: TimeInterval = 5
    ) -> NetServicePublisher {
        .init(netService: self, timeout: timeout, monitorDevice: strategy)
    }
}

/// A Combine `Publisher` that resolves a `NetService` to its address(es) and TXT record.
///
/// Wraps the `NetServiceDelegate` callbacks into a Combine stream. Use `NWEndpointPublisher`
/// for new code; `NetServicePublisher` is valuable when a `NetService` instance is already
/// available (e.g. from `NetServiceBrowserPublisher`).
///
/// ## Resolve and get IP addresses
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// let service = NetService(domain: "local.", type: "_ssh._tcp.", name: "macbook")
///
/// service.publisher(monitorDevice: .doNotMonitorTXTUpdates, timeout: 10)
///     .compactMap { event -> [String]? in
///         guard case .didResolveAddress = event.type else { return nil }
///         return event.netService.parsedAddresses()
///     }
///     .first()
///     .sink(receiveCompletion: { _ in }, receiveValue: { ips in
///         print("resolved IPs:", ips)
///     })
///     .store(in: &cancellables)
/// ```
///
/// ## Monitor TXT record updates
///
/// ```swift
/// service.publisher(monitorDevice: .keepMonitoringTXTUpdates)
///     .compactMap { event -> [String: Data]? in
///         guard case let .didUpdateTXTRecord(txt) = event.type else { return nil }
///         return txt
///     }
///     .sink { txt in print("TXT updated:", txt) }
///     .store(in: &cancellables)
/// ```
public struct NetServicePublisher {
    private let netService: NetService
    private let timeout: TimeInterval
    private let monitorDevice: NetServiceTXTRecordsMonitorStrategy

    public init(netService: NetService, timeout: TimeInterval, monitorDevice: NetServiceTXTRecordsMonitorStrategy) {
        self.netService = netService
        self.timeout = timeout
        self.monitorDevice = monitorDevice
    }

    public init(
        name: String,
        domain: String,
        type: String,
        timeout: TimeInterval,
        monitorDevice: NetServiceTXTRecordsMonitorStrategy
    ) {
        self.init(
            netService: .init(domain: domain, type: type, name: name),
            timeout: timeout,
            monitorDevice: monitorDevice
        )
    }
}

extension NetServicePublisher: Publisher {
    public typealias Output = Event
    public typealias Failure = NetServiceError

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(
            subscriber: subscriber,
            netService: netService,
            timeout: timeout,
            monitorDevice: monitorDevice))
    }
}

extension NetServicePublisher {
    private class Subscription<S: Subscriber>: NSObject, Combine.Subscription, NetServiceDelegate
    where S.Input == Output, S.Failure == Failure {
        private var buffer: DemandBuffer<S>?
        private let netService: NetService
        private let timeout: TimeInterval
        private let monitorDevice: NetServiceTXTRecordsMonitorStrategy
        private let lock = NSRecursiveLock()
        private var started = false

        init(
            subscriber: S,
            netService: NetService,
            timeout: TimeInterval,
            monitorDevice: NetServiceTXTRecordsMonitorStrategy
        ) {
            self.netService = netService
            self.buffer = DemandBuffer(subscriber: subscriber)
            self.timeout = timeout
            self.monitorDevice = monitorDevice
            super.init()
            netService.delegate = self
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }
            lock.lock()
            if !started && demand > .none {
                started = true
                lock.unlock()
                start()
            } else {
                lock.unlock()
            }
            _ = buffer.demand(demand)
        }

        func cancel() {
            lock.lock(); buffer = nil; started = false; lock.unlock()
            if monitorDevice == .keepMonitoringTXTUpdates { netService.stopMonitoring() }
        }

        private func start() {
            if monitorDevice == .keepMonitoringTXTUpdates { netService.startMonitoring() }
            netService.resolve(withTimeout: timeout)
        }

        func netServiceWillPublish(_ s: NetService) {
            _ = buffer?.buffer(value: .init(netService: s, type: .willPublish))
        }

        func netServiceDidPublish(_ s: NetService) {
            _ = buffer?.buffer(value: .init(netService: s, type: .didPublish))
        }

        func netServiceWillResolve(_ s: NetService) {
            _ = buffer?.buffer(value: .init(netService: s, type: .willResolve))
        }

        func netServiceDidResolveAddress(_ s: NetService) {
            _ = buffer?.buffer(value: .init(netService: s, type: .didResolveAddress(s.addresses ?? [])))
        }

        func netService(_ s: NetService, didUpdateTXTRecord data: Data) {
            let txt = NetService.dictionary(fromTXTRecord: data)
            _ = buffer?.buffer(value: .init(netService: s, type: .didUpdateTXTRecord(txtRecord: txt)))
        }

        func netService(_ s: NetService, didAcceptConnectionWith i: InputStream, outputStream o: OutputStream) {
            _ = buffer?.buffer(value: .init(netService: s, type: .didAcceptConnectionWith(inputStream: i, outputStream: o)))
        }

        func netServiceDidStop(_ s: NetService) {
            buffer?.complete(completion: .finished)
        }

        func netService(_ s: NetService, didNotPublish dict: [String: NSNumber]) {
            buffer?.complete(completion: .failure(.didNotPublish(netService: s, errorDict: dict)))
        }

        func netService(_ s: NetService, didNotResolve dict: [String: NSNumber]) {
            guard let domain = dict["NSNetServicesErrorDomain"]?.intValue,
                  let code   = dict["NSNetServicesErrorCode"]?.intValue else { return }
            if code == NetService.ErrorCode.timeoutError.rawValue {
                buffer?.complete(completion: .failure(.netServiceTimeout))
            } else {
                buffer?.complete(completion: .failure(.didNotResolve(
                    netService: s, errorDict: dict, errorDomain: domain, errorCode: code)))
            }
        }
    }
}

// MARK: - Model

extension NetServicePublisher {
    public struct Event: Equatable {
        public let netService: NetService
        public let type: EventType

        public init(netService: NetService, type: EventType) {
            self.netService = netService
            self.type = type
        }
    }

    public enum EventType: Equatable {
        case willPublish
        case didPublish
        case willResolve
        case didResolveAddress([Data])
        case didUpdateTXTRecord(txtRecord: [String: Data])
        case didAcceptConnectionWith(inputStream: InputStream, outputStream: OutputStream)
    }

    public enum NetServiceError: Error {
        case didNotPublish(netService: NetService, errorDict: [String: NSNumber])
        case didNotResolve(netService: NetService, errorDict: [String: NSNumber],
                           errorDomain: Int, errorCode: Int)
        case netServiceTimeout
    }
}
#endif
