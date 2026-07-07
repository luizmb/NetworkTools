// SPDX-License-Identifier: Apache-2.0

// MCNearbyServiceBrowserDelegate hands back discoveryInfo as [String: String]? mirroring the
// underlying Bonjour TXT record (nil — no TXT — vs [:] — empty TXT — differ semantically), so
// the optional collection is kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Foundation
import FP
@preconcurrency import MultipeerConnectivity
import ReactiveConcurrency

/// A ReactiveConcurrency `Publisher` wrapping `MCNearbyServiceBrowser`.
///
/// A fresh browser is created on each subscription; browsing stops when the subscription
/// terminates. Emissions are `MultipeerBrowserEvent`; a `.failure` is sent if the browser
/// fails to start, followed by stream completion.
public func multipeerBrowserStream(
    myselfAsPeer: MCPeerID,
    serviceType: String
) -> Publisher<MultipeerBrowserEvent, Error> {
    Publisher { continuation in
        let delegate = MultipeerBrowserStreamDelegate(
            continuation: continuation,
            peer: myselfAsPeer,
            serviceType: serviceType
        )
        delegate.start()
        await continuation.suspendUntilCancelled()
        delegate.stop()
    }
}

private final class MultipeerBrowserStreamDelegate: NSObject, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    private let continuation: Publisher<MultipeerBrowserEvent, Error>.Continuation
    private let browser: MCNearbyServiceBrowser

    init(
        continuation: Publisher<MultipeerBrowserEvent, Error>.Continuation,
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
        continuation.yield(.foundPeer(peerID: peerID, info: info, browser: browser))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        continuation.yield(.lostPeer(peerID: peerID))
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        continuation.fail(error)
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
