// MCNearbyServiceAdvertiser exposes discoveryInfo as [String: String]? where nil (no TXT
// data) is semantically distinct from [:] (empty TXT data), so the optional collection is
// kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

/// Combine `Publisher` wrapping `MCNearbyServiceAdvertiser`.
///
/// A fresh advertiser is created per subscription; advertising stops when the subscription is
/// cancelled. Backpressure is not implemented — demand is honoured only as "advertising on /
/// off".
public struct MultipeerAdvertiserPublisher: Publisher {
    public typealias Output = MultipeerAdvertiserEvent
    public typealias Failure = Error

    private let peer: MCPeerID
    private let serviceType: String
    private let discoveryInfo: [String: String]?

    public init(myselfAsPeer: MCPeerID, serviceType: String, discoveryInfo: [String: String]? = nil) {
        self.peer = myselfAsPeer
        self.serviceType = serviceType
        self.discoveryInfo = discoveryInfo
    }

    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = MultipeerAdvertiserSubscription(
            subscriber: subscriber,
            peer: peer,
            serviceType: serviceType,
            discoveryInfo: discoveryInfo
        )
        subscriber.receive(subscription: subscription)
    }
}

final class MultipeerAdvertiserSubscription<S: Subscriber>: NSObject, MCNearbyServiceAdvertiserDelegate, Subscription, @unchecked Sendable
where S.Input == MultipeerAdvertiserEvent, S.Failure == Error {
    private var requested: Subscribers.Demand = .none
    private var subscriber: S?
    private let advertiser: MCNearbyServiceAdvertiser

    init(subscriber: S, peer: MCPeerID, serviceType: String, discoveryInfo: [String: String]? = nil) {
        self.subscriber = subscriber
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: discoveryInfo, serviceType: serviceType)
        super.init()
        advertiser.delegate = self
    }

    func request(_ demand: Subscribers.Demand) {
        increaseDemand(demand)
    }

    func cancel() {
        advertiser.stopAdvertisingPeer()
        requested = .none
        subscriber = nil
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        increaseDemand(
            subscriber?.receive(.didReceiveInvitationFromPeer(peerID, context: context, handler: invitationHandler))
        )
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        subscriber?.receive(completion: .failure(error))
    }

    private func increaseDemand(_ increment: Subscribers.Demand?) {
        DispatchQueue.main.async { [self] in
            let first = requested == .none
            requested += increment ?? .none
            if first && requested != .none {
                advertiser.startAdvertisingPeer()
            }
        }
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
