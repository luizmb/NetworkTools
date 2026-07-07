// SPDX-License-Identifier: Apache-2.0

#if canImport(Network)
import Foundation
import FP
@preconcurrency import Network
import ReactiveConcurrency

/// A ReactiveConcurrency `Publisher` wrapping `NWBrowser` for Bonjour service discovery.
///
/// A fresh browser is started on each subscription; browsing stops when the subscription
/// terminates. Emissions are `BonjourBrowseEvent`; a failure completes the stream.
///
/// Events carry ``BonjourServiceInfo`` values (name, type, domain, TXT record) rather
/// than Apple-specific `NWEndpoint` types, so results can be processed on any platform.
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
    Publisher { continuation in
        let delegate = NWBrowserStreamDelegate(browser: browser, continuation: continuation)
        delegate.start()
        await continuation.suspendUntilCancelled()
        delegate.stop()
    }
}

// MARK: - Private delegate

private final class NWBrowserStreamDelegate: @unchecked Sendable {
    private let browser: NWBrowser
    private let continuation: Publisher<BonjourBrowseEvent, Error>.Continuation

    init(
        browser: NWBrowser,
        continuation: Publisher<BonjourBrowseEvent, Error>.Continuation
    ) {
        self.browser = browser
        self.continuation = continuation

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(error): self?.handleError(error)
            case let .waiting(error): self?.handleError(error)
            case .cancelled: self?.continuation.finish()
            case .setup,
                 .ready: break
            @unknown default: break
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
                continuation.yield(.found(info))
            }
        case let .removed(result):
            if let info = BonjourServiceInfo(from: result) {
                continuation.yield(.removed(info))
            }
        case let .changed(old, new, _):
            if let oldInfo = BonjourServiceInfo(from: old),
               let newInfo = BonjourServiceInfo(from: new) {
                continuation.yield(.updated(from: oldInfo, to: newInfo))
            }
        @unknown default:
            break
        }
    }

    private func handleError(_ error: NWError) {
        if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
            continuation.fail(BonjourBrowseError.permissionDenied)
        } else {
            continuation.fail(BonjourBrowseError.didNotSearch(error: error))
        }
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
