#if canImport(Network)
import Foundation
import FP
import ReactiveConcurrency
@preconcurrency import Network

/// Native ``DeferredStream`` wrapping `NWBrowser` for Bonjour service discovery.
///
/// A fresh browser is started on each iteration; browsing stops when the iterator
/// terminates. Emissions are `Result<BonjourBrowseEvent, Error>`.
///
/// Events carry ``BonjourServiceInfo`` values (name, type, domain, TXT record) rather
/// than Apple-specific `NWEndpoint` types, so results can be processed on any platform.
///
/// This implementation does not depend on Combine.
///
/// ## Creating from a service type
///
/// ```swift
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     switch result {
///     case .success(.found(let info)):
///         print("found:", info.name)
///         let resolved = try await bonjourResolve(info).run().get()
///         if let url = resolved.webSocketURL() { /* connect */ }
///     case .success(.removed(let info)):
///         print("gone:", info.name)
///     case .success(.updated(let old, let new)):
///         print("updated:", old.name, "→", new.name)
///     case .failure(let err):
///         print("error:", err)
///     }
/// }
/// ```
///
/// ## Using a pre-configured browser
///
/// ```swift
/// let browser = NWBrowser(
///     for: .bonjourWithTXTRecord(type: "_myapp._tcp.", domain: nil),
///     using: .tcp
/// )
/// for await result in bonjourBrowserStream(browser: browser) { ... }
/// ```
public func bonjourBrowserStream(
    serviceType: String,
    domain: String? = nil,
    params: NWParameters = .tcp
) -> Publisher<BonjourBrowseEvent, Error> {
    bonjourBrowserStream(browser: NWBrowser(
        for: .bonjourWithTXTRecord(type: serviceType, domain: domain),
        using: params
    ))
}

/// Variant for when an `NWBrowser` has already been configured externally.
///
/// All state and results-changed handlers on the provided browser will be
/// overwritten when the stream starts.
public func bonjourBrowserStream(
    browser: NWBrowser
) -> Publisher<BonjourBrowseEvent, Error> {
    DeferredStream {
        AsyncStream { continuation in
            let delegate = NWBrowserStreamDelegate(browser: browser, continuation: continuation)
            continuation.onTermination = { @Sendable _ in delegate.stop() }
            delegate.start()
        }
    }
    .eraseToThrowingPublisher()
}

// MARK: - Private delegate

private final class NWBrowserStreamDelegate: @unchecked Sendable {
    private let browser: NWBrowser
    private let continuation: AsyncStream<Result<BonjourBrowseEvent, Error>>.Continuation

    init(
        browser: NWBrowser,
        continuation: AsyncStream<Result<BonjourBrowseEvent, Error>>.Continuation
    ) {
        self.browser = browser
        self.continuation = continuation

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(error):  self?.handleError(error)
            case let .waiting(error): self?.handleError(error)
            case .cancelled:          self?.continuation.finish()
            case .setup, .ready:      break
            @unknown default:         break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] _, changes in
            changes.forEach { self?.handle(change: $0) }
        }
    }

    func start() { browser.start(queue: .main) }
    func stop() { browser.cancel() }

    private func handle(change: NWBrowser.Result.Change) {
        switch change {
        case .identical:
            break
        case let .added(result):
            if let info = BonjourServiceInfo(from: result) {
                continuation.yield(.success(.found(info)))
            }
        case let .removed(result):
            if let info = BonjourServiceInfo(from: result) {
                continuation.yield(.success(.removed(info)))
            }
        case let .changed(old, new, _):
            if let oldInfo = BonjourServiceInfo(from: old),
               let newInfo = BonjourServiceInfo(from: new) {
                continuation.yield(.success(.updated(from: oldInfo, to: newInfo)))
            }
        @unknown default:
            break
        }
    }

    private func handleError(_ error: NWError) {
        if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
            continuation.yield(.failure(BonjourBrowseError.permissionDenied))
        } else {
            continuation.yield(.failure(BonjourBrowseError.didNotSearch(error: error)))
        }
        continuation.finish()
    }
}

// MARK: - NWBrowser.Result → BonjourServiceInfo

private extension BonjourServiceInfo {
    init?(from result: NWBrowser.Result) {
        guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
        self.init(name: name, type: type, domain: domain, txt: result.metadata.txt)
    }
}
#endif
