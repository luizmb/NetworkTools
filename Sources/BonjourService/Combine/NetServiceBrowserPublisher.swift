#if canImport(Combine)
import Combine
import Core
import Foundation

extension NetServiceBrowser {
    /// Returns a publisher for the given service type and domain.
    ///
    /// Equivalent to `NetServiceBrowserPublisher(netServiceBrowser: self, ...)`.
    public func publisher(serviceOfType type: String, inDomain domain: String) -> NetServiceBrowserPublisher {
        .init(netServiceBrowser: self, serviceOfType: type, inDomain: domain)
    }
}

/// A Combine `Publisher` that streams Bonjour service-discovery events from `NetServiceBrowser`.
///
/// `NetServiceBrowserPublisher` wraps the `NetServiceBrowserDelegate` callbacks into a
/// Combine stream. Use `NWBrowserPublisher` for new code; this type is provided for
/// compatibility with APIs that surface `NetService` objects directly.
///
/// ## Usage
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// NetServiceBrowser()
///     .publisher(serviceOfType: "_http._tcp.", inDomain: "local.")
///     .sink(
///         receiveCompletion: { print("done:", $0) },
///         receiveValue: { event in
///             switch event.type {
///             case .didFind(let service, _):
///                 print("found:", service.name)
///             case .didRemove(let service, _):
///                 print("lost:", service.name)
///             default:
///                 break
///             }
///         }
///     )
///     .store(in: &cancellables)
/// ```
public struct NetServiceBrowserPublisher {
    private let netServiceBrowser: NetServiceBrowser
    private let services: String
    private let domain: String

    public init(netServiceBrowser: NetServiceBrowser, serviceOfType services: String, inDomain domain: String) {
        self.netServiceBrowser = netServiceBrowser
        self.services = services
        self.domain = domain
    }
}

extension NetServiceBrowserPublisher: Publisher {
    public typealias Output = Event
    public typealias Failure = NetServiceBrowserError

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(
            subscriber: subscriber,
            netServiceBrowser: netServiceBrowser,
            services: services,
            domain: domain))
    }
}

extension NetServiceBrowserPublisher {
    private class Subscription<S: Subscriber>: NSObject, Combine.Subscription, NetServiceBrowserDelegate
    where S.Input == Output, S.Failure == Failure {
        private var buffer: DemandBuffer<S>?
        private let netServiceBrowser: NetServiceBrowser
        private let services: String
        private let domain: String
        private let lock = NSRecursiveLock()
        private var started = false

        init(subscriber: S, netServiceBrowser: NetServiceBrowser, services: String, domain: String) {
            self.netServiceBrowser = netServiceBrowser
            self.buffer = DemandBuffer(subscriber: subscriber)
            self.services = services
            self.domain = domain
            super.init()
            netServiceBrowser.delegate = self
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }
            lock.lock()
            if !started && demand > .none { started = true; lock.unlock(); start() }
            else { lock.unlock() }
            _ = buffer.demand(demand)
        }

        func cancel() { buffer = nil; started = false; netServiceBrowser.stop() }
        private func start() { netServiceBrowser.searchForServices(ofType: services, inDomain: domain) }

        func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
            _ = buffer?.buffer(value: .init(netServiceBrowser: b, type: .didFind(service: s, moreComing: moreComing)))
        }

        func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
            _ = buffer?.buffer(value: .init(netServiceBrowser: b, type: .didRemove(service: s, moreComing: moreComing)))
        }

        func netServiceBrowser(_ b: NetServiceBrowser, didNotSearch dict: [String: NSNumber]) {
            buffer?.complete(completion: .failure(.didNotSearch(netServiceBrowser: b, errorDict: dict)))
        }

        func netServiceBrowser(_ b: NetServiceBrowser, didFindDomain d: String, moreComing: Bool) {
            _ = buffer?.buffer(value: .init(netServiceBrowser: b, type: .didFindDomain(domainString: d, moreComing: moreComing)))
        }

        func netServiceBrowserWillSearch(_ b: NetServiceBrowser) {
            _ = buffer?.buffer(value: .init(netServiceBrowser: b, type: .willSearch))
        }

        func netServiceBrowser(_ b: NetServiceBrowser, didRemoveDomain d: String, moreComing: Bool) {
            _ = buffer?.buffer(value: .init(netServiceBrowser: b, type: .didRemoveDomain(domainString: d, moreComing: moreComing)))
        }

        func netServiceBrowserDidStopSearch(_ b: NetServiceBrowser) {
            buffer?.complete(completion: .finished)
        }
    }
}

// MARK: - Model

extension NetServiceBrowserPublisher {
    public struct Event {
        public let netServiceBrowser: NetServiceBrowser
        public let type: EventType

        public init(netServiceBrowser: NetServiceBrowser, type: EventType) {
            self.netServiceBrowser = netServiceBrowser
            self.type = type
        }
    }

    public enum EventType {
        case willSearch
        case didFindDomain(domainString: String, moreComing: Bool)
        case didFind(service: NetService, moreComing: Bool)
        case didRemoveDomain(domainString: String, moreComing: Bool)
        case didRemove(service: NetService, moreComing: Bool)
    }

    public enum NetServiceBrowserError: Error {
        case didNotSearch(netServiceBrowser: NetServiceBrowser, errorDict: [String: NSNumber])
    }
}
#endif
