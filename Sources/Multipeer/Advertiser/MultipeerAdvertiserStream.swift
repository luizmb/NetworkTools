// SPDX-License-Identifier: Apache-2.0

// MCNearbyServiceAdvertiser exposes discoveryInfo as [String: String]? where nil (no TXT
// data) is semantically distinct from [:] (empty TXT data), so the optional collection is
// kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Foundation
import FP
@preconcurrency import MultipeerConnectivity
import ReactiveConcurrency

/// A ReactiveConcurrency `Publisher` wrapping `MCNearbyServiceAdvertiser`.
///
/// A fresh advertiser is created on each subscription; advertising stops when the subscription
/// terminates. Emissions are `MultipeerAdvertiserEvent`; a `.failure` is sent if the advertiser
/// fails to start, followed by stream completion.
public func multipeerAdvertiserStream(
    myselfAsPeer: MCPeerID,
    serviceType: String,
    discoveryInfo: [String: String]? = nil
) -> Publisher<MultipeerAdvertiserEvent, Error> {
    Publisher { continuation in
        let delegate = MultipeerAdvertiserStreamDelegate(
            continuation: continuation,
            peer: myselfAsPeer,
            serviceType: serviceType,
            discoveryInfo: discoveryInfo
        )
        delegate.start()
        await continuation.suspendUntilCancelled()
        delegate.stop()
    }
}

private final class MultipeerAdvertiserStreamDelegate: NSObject, MCNearbyServiceAdvertiserDelegate, @unchecked Sendable {
    private let continuation: Publisher<MultipeerAdvertiserEvent, Error>.Continuation
    private let advertiser: MCNearbyServiceAdvertiser

    init(
        continuation: Publisher<MultipeerAdvertiserEvent, Error>.Continuation,
        peer: MCPeerID,
        serviceType: String,
        discoveryInfo: [String: String]?
    ) {
        self.continuation = continuation
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: discoveryInfo, serviceType: serviceType)
        super.init()
        advertiser.delegate = self
    }

    func start() {
        DispatchQueue.main.async { [advertiser] in
            advertiser.startAdvertisingPeer()
        }
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        continuation.yield(.didReceiveInvitationFromPeer(peerID, context: context, handler: invitationHandler))
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        continuation.fail(error)
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
