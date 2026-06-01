// nil TXT (no record) is semantically distinct from [:] (empty record).
// swiftlint:disable discouraged_optional_collection
#if canImport(Network)
import Foundation
import FP
@preconcurrency import Network

/// Native ``DeferredStream`` wrapping `NWBrowser` for Bonjour service discovery.
///
/// A fresh browser is created on each iteration; browsing stops when the iterator
/// terminates. Emissions are `Result<BonjourBrowseEvent, Error>` — `.failure` is
/// sent on permission denial or fatal browser error, followed by stream completion.
///
/// Events carry ``BonjourServiceInfo`` values (name, type, domain, TXT record) rather
/// than Apple-specific `NWEndpoint` types, so results can be processed on any platform.
///
/// This implementation does not depend on Combine.
///
/// ## Example
///
/// ```swift
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     switch result {
///     case .success(.found(let info)):
///         print("found:", info.name)
///     case .success(.removed(let info)):
///         print("gone:", info.name)
///     case .success(.updated(let old, let new)):
///         print("updated:", old.name, "→", new.name)
///     case .failure(let err):
///         print("error:", err)
///     }
/// }
/// ```
public func bonjourBrowserStream(
    serviceType: String,
    domain: String? = nil,
    params: NWParameters = .tcp
) -> DeferredStream<Result<BonjourBrowseEvent, Error>> {
    DeferredStream {
        AsyncStream { continuation in
            let delegate = NWBrowserStreamDelegate(
                serviceType: serviceType,
                domain: domain,
                params: params,
                continuation: continuation
            )
            continuation.onTermination = { @Sendable _ in delegate.stop() }
            delegate.start()
        }
    }
}

private final class NWBrowserStreamDelegate: @unchecked Sendable {
    private let browser: NWBrowser
    private let continuation: AsyncStream<Result<BonjourBrowseEvent, Error>>.Continuation

    init(
        serviceType: String,
        domain: String?,
        params: NWParameters,
        continuation: AsyncStream<Result<BonjourBrowseEvent, Error>>.Continuation
    ) {
        self.continuation = continuation
        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: domain),
            using: params
        )

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(error):  self?.handleError(error)
            case let .waiting(error): self?.handleError(error)
            case .cancelled:          self?.continuation.finish()
            case .setup, .ready:      break
            @unknown default:         break
            }
        }

        browser.browseResultsChangedHandler = { [continuation] _, changes in
            for change in changes {
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
        }
    }

    func start() { browser.start(queue: .main) }
    func stop()  { browser.cancel() }

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
// swiftlint:enable discouraged_optional_collection
