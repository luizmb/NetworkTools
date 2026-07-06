// SPDX-License-Identifier: Apache-2.0

// nil TXT (no record) is semantically distinct from [:] (empty record).
// swiftlint:disable discouraged_optional_collection
#if canImport(Combine)
import Combine
import Core
import Foundation
import Network

public extension NWBrowser {
    /// A Combine publisher that streams service-discovery events from this browser.
    ///
    /// Shorthand for `NWBrowserPublisher(browser: self)`.
    var publisher: NWBrowserPublisher { .init(browser: self) }
}

/// A Combine `Publisher` that streams Bonjour service-discovery events from `NWBrowser`.
///
/// `NWBrowserPublisher` wraps `NWBrowser`'s state and results-changed handlers into a
/// backpressure-aware Combine stream. Browsing starts lazily — only when the first
/// subscriber signals demand.
///
/// ## Basic usage
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// NWBrowserPublisher(serviceType: "_myapp._tcp.", domain: nil)
///     .sink(
///         receiveCompletion: { completion in
///             switch completion {
///             case .finished:       print("browser stopped")
///             case .failure(let e): print("error:", e)
///             }
///         },
///         receiveValue: { event in
///             switch event {
///             case .didFind(let endpoint, let txt):
///                 print("found:", endpoint, "txt:", txt ?? [:])
///             case .didRemove(let endpoint, _):
///                 print("lost:", endpoint)
///             case .didUpdate(_, let new, let txt, _):
///                 print("updated:", new, "txt:", txt ?? [:])
///             }
///         }
///     )
///     .store(in: &cancellables)
/// ```
///
/// ## With an existing NWBrowser
///
/// ```swift
/// let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp.", domain: nil),
///                          using: .tcp)
/// browser.publisher
///     .map(\.endpoint)
///     .sink { print($0) }
///     .store(in: &cancellables)
/// ```
public struct NWBrowserPublisher {
    private let browser: NWBrowser

    public init(browser: NWBrowser) {
        self.browser = browser
    }

    /// Convenience init: creates and configures an `NWBrowser` internally.
    ///
    /// - Parameters:
    ///   - serviceType: Bonjour service type, e.g. `"_myapp._tcp."`.
    ///   - domain: Search domain; `nil` searches the local link and wide-area domains.
    ///   - params: Network parameters; defaults to plain TCP.
    public init(serviceType: String, domain: String?, params: NWParameters = .tcp) {
        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: domain),
            using: params
        )
    }

    /// Convenience init using a `ServiceDescription`.
    public init(serviceDescription: ServiceDescription, params: NWParameters = .tcp) {
        self.init(serviceType: serviceDescription.serviceName, domain: serviceDescription.domain, params: params)
    }
}

extension NWBrowserPublisher: Publisher {
    public typealias Output = Event
    public typealias Failure = NWBrowserError

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(subscriber: subscriber, browser: browser))
    }
}

extension NWBrowserPublisher {
    private class Subscription<S: Subscriber>: Combine.Subscription, @unchecked Sendable
    where S.Input == Output, S.Failure == Failure {
        private var buffer: DemandBuffer<S>?
        private let browser: NWBrowser
        private let lock = NSRecursiveLock()
        private var started = false

        init(subscriber: S, browser: NWBrowser) {
            self.browser = browser
            buffer = DemandBuffer(subscriber: subscriber)

            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case let .failed(error): self?.handleError(error)
                case let .waiting(error): self?.handleError(error)
                case .cancelled: self?.buffer?.complete(completion: .finished)
                case .setup,
                     .ready: break
                @unknown default: break
                }
            }

            browser.browseResultsChangedHandler = { [weak self] _, changes in
                guard let self else { return }
                for change in changes {
                    switch change {
                    case .identical: break
                    case let .added(r):
                        _ = buffer?.buffer(value: .didFind(endpoint: r.endpoint, txt: r.metadata.txt))
                    case let .removed(r):
                        _ = buffer?.buffer(value: .didRemove(endpoint: r.endpoint, txt: r.metadata.txt))
                    case let .changed(old, new, flags):
                        _ = buffer?.buffer(value: .didUpdate(
                            oldEndpoint: old.endpoint,
                            newEndpoint: new.endpoint,
                            txt: new.metadata.txt,
                            flags: flags
                        ))
                    @unknown default: break
                    }
                }
            }
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }
            lock.lock()
            if !started, demand > .none {
                started = true
                lock.unlock()
                start()
            } else {
                lock.unlock()
            }
            _ = buffer.demand(demand)
        }

        func cancel() { buffer = nil; started = false; browser.cancel() }
        private func start() { browser.start(queue: .main) }

        private func handleError(_ error: NWError) {
            if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
                buffer?.complete(completion: .failure(.bonjourPermissionDenied))
            } else {
                buffer?.complete(completion: .failure(.didNotSearch(error: error)))
            }
        }
    }
}

// MARK: - Model

public extension NWBrowserPublisher {
    enum Event {
        /// A service matching the search descriptor appeared on the network.
        case didFind(endpoint: NWEndpoint, txt: [String: String]?)
        /// A previously discovered service is no longer available.
        case didRemove(endpoint: NWEndpoint, txt: [String: String]?)
        /// A previously discovered service changed (e.g. appeared on a new interface).
        case didUpdate(
            oldEndpoint: NWEndpoint,
            newEndpoint: NWEndpoint,
            txt: [String: String]?,
            flags: NWBrowser.Result.Change.Flags
        )
    }

    enum NWBrowserError: Error {
        /// The user has not granted local-network access to the app.
        case bonjourPermissionDenied
        /// The browser failed with an underlying network error.
        case didNotSearch(error: NWError)
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
