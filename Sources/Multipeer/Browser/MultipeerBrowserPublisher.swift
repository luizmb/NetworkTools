// MCNearbyServiceBrowserDelegate hands back discoveryInfo as [String: String]? mirroring the
// underlying Bonjour TXT record (nil — no TXT — vs [:] — empty TXT — differ semantically), so
// the optional collection is kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

/// Combine `Publisher` wrapping `MCNearbyServiceBrowser`.
///
/// A fresh browser is created per subscription; browsing stops when the subscription is
/// cancelled. Backpressure is not implemented.
public struct MultipeerBrowserPublisher: Publisher {
    public typealias Output = MultipeerBrowserEvent
    public typealias Failure = Error

    private let peerID: MCPeerID
    private let serviceType: String

    public init(myselfAsPeer: MCPeerID, serviceType: String) {
        self.peerID = myselfAsPeer
        self.serviceType = serviceType
    }

    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = MultipeerBrowserSubscription(subscriber: subscriber, peer: peerID, serviceType: serviceType)
        subscriber.receive(subscription: subscription)
    }
}

final class MultipeerBrowserSubscription<S: Subscriber>: NSObject, MCNearbyServiceBrowserDelegate, Subscription, @unchecked Sendable
where S.Input == MultipeerBrowserEvent, S.Failure == Error {
    private var requested: Subscribers.Demand = .none
    private var subscriber: S?
    private let browser: MCNearbyServiceBrowser

    init(subscriber: S, peer: MCPeerID, serviceType: String) {
        self.subscriber = subscriber
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        super.init()
        browser.delegate = self
    }

    func request(_ demand: Subscribers.Demand) {
        increaseDemand(demand)
    }

    func cancel() {
        browser.stopBrowsingForPeers()
        requested = .none
        subscriber = nil
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        increaseDemand(
            subscriber?.receive(.foundPeer(peerID: peerID, info: info, browser: browser))
        )
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        increaseDemand(
            subscriber?.receive(.lostPeer(peerID: peerID))
        )
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        subscriber?.receive(completion: .failure(error))
    }

    private func increaseDemand(_ increment: Subscribers.Demand?) {
        DispatchQueue.main.async { [self] in
            let first = requested == .none
            requested += increment ?? .none
            if first && requested != .none {
                browser.startBrowsingForPeers()
            }
        }
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
