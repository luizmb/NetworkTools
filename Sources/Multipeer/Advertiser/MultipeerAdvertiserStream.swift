// MCNearbyServiceAdvertiser exposes discoveryInfo as [String: String]? where nil (no TXT
// data) is semantically distinct from [:] (empty TXT data), so the optional collection is
// kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Foundation
import FP
import ReactiveConcurrency
@preconcurrency import MultipeerConnectivity

/// Native ``DeferredStream`` wrapping `MCNearbyServiceAdvertiser`.
///
/// A fresh advertiser is created on each iteration (`for await`); advertising stops when the
/// iterator terminates. Emissions are `Result<MultipeerAdvertiserEvent, Error>` — `.failure`
/// is sent if the advertiser fails to start, followed by stream completion.
///
/// This implementation does not depend on Combine.
public func multipeerAdvertiserStream(
    myselfAsPeer: MCPeerID,
    serviceType: String,
    discoveryInfo: [String: String]? = nil
) -> Publisher<MultipeerAdvertiserEvent, Error> {
    DeferredStream {
        AsyncStream { continuation in
            let delegate = MultipeerAdvertiserStreamDelegate(
                continuation: continuation,
                peer: myselfAsPeer,
                serviceType: serviceType,
                discoveryInfo: discoveryInfo
            )
            continuation.onTermination = { @Sendable _ in delegate.stop() }
            delegate.start()
        }
    }
    .eraseToThrowingPublisher()
}

private final class MultipeerAdvertiserStreamDelegate: NSObject, MCNearbyServiceAdvertiserDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<Result<MultipeerAdvertiserEvent, Error>>.Continuation
    private let advertiser: MCNearbyServiceAdvertiser

    init(
        continuation: AsyncStream<Result<MultipeerAdvertiserEvent, Error>>.Continuation,
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
        continuation.yield(
            .success(.didReceiveInvitationFromPeer(peerID, context: context, handler: invitationHandler))
        )
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        continuation.yield(.failure(error))
        continuation.finish()
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
