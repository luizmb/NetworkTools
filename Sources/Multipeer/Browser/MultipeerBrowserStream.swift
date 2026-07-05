// MCNearbyServiceBrowserDelegate hands back discoveryInfo as [String: String]? mirroring the
// underlying Bonjour TXT record (nil — no TXT — vs [:] — empty TXT — differ semantically), so
// the optional collection is kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Foundation
import FP
import ReactiveConcurrency
@preconcurrency import MultipeerConnectivity

/// Native ``DeferredStream`` wrapping `MCNearbyServiceBrowser`.
///
/// A fresh browser is created on each iteration; browsing stops when the iterator terminates.
/// Emissions are `Result<MultipeerBrowserEvent, Error>` — `.failure` is sent if the browser
/// fails to start, followed by stream completion.
///
/// This implementation does not depend on Combine.
public func multipeerBrowserStream(
    myselfAsPeer: MCPeerID,
    serviceType: String
) -> Publisher<MultipeerBrowserEvent, Error> {
    DeferredStream {
        AsyncStream { continuation in
            let delegate = MultipeerBrowserStreamDelegate(
                continuation: continuation,
                peer: myselfAsPeer,
                serviceType: serviceType
            )
            continuation.onTermination = { @Sendable _ in delegate.stop() }
            delegate.start()
        }
    }
    .eraseToThrowingPublisher()
}

private final class MultipeerBrowserStreamDelegate: NSObject, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<Result<MultipeerBrowserEvent, Error>>.Continuation
    private let browser: MCNearbyServiceBrowser

    init(
        continuation: AsyncStream<Result<MultipeerBrowserEvent, Error>>.Continuation,
        peer: MCPeerID,
        serviceType: String
    ) {
        self.continuation = continuation
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        super.init()
        browser.delegate = self
    }

    func start() {
        DispatchQueue.main.async { [browser] in
            browser.startBrowsingForPeers()
        }
    }

    func stop() {
        browser.stopBrowsingForPeers()
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        continuation.yield(.success(.foundPeer(peerID: peerID, info: info, browser: browser)))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        continuation.yield(.success(.lostPeer(peerID: peerID)))
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        continuation.yield(.failure(error))
        continuation.finish()
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
