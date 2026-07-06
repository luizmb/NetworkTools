// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Combine
import Foundation
import FP
@preconcurrency import MultipeerConnectivity
import ReactiveConcurrency

/// A Multipeer session exposing both Combine and `DeferredStream`/`DeferredTask` APIs side by
/// side. The two API families are implemented independently — the deferred-concurrency side
/// does not go through the Combine subjects, so the same pattern carries over to Linux-capable
/// transports where Combine isn't available.
public class MultipeerSession: NSObject, MCSessionDelegate, @unchecked Sendable {
    public let session: MCSession

    private let _messages = Combine.PassthroughSubject<MultipeerSessionReceivedMessage, Never>()
    private let _connections = Combine.PassthroughSubject<MultipeerSessionConnectionStatusEvent, Never>()
    private let messagesMulticaster = AsyncMulticaster<MultipeerSessionReceivedMessage>()
    private let connectionsMulticaster = AsyncMulticaster<MultipeerSessionConnectionStatusEvent>()

    public init(myselfAsPeer: MCPeerID) {
        session = MCSession(peer: myselfAsPeer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    deinit {
        messagesMulticaster.finish()
        connectionsMulticaster.finish()
    }

    // MARK: - Combine API

    public var messages: Combine.AnyPublisher<MultipeerSessionReceivedMessage, Never> {
        _messages.eraseToAnyPublisher()
    }

    public var connections: Combine.AnyPublisher<MultipeerSessionConnectionStatusEvent, Never> {
        _connections.eraseToAnyPublisher()
    }

    /// Invites a peer and emits its `MCPeerID` each time it becomes connected.
    /// The invitation is sent on subscription.
    public func invite(
        peer: MCPeerID,
        browser: MCNearbyServiceBrowser,
        context: Data?,
        timeout: TimeInterval
    ) -> Combine.AnyPublisher<MCPeerID, Never> {
        _connections
            .filter { event in
                guard case let .peerConnected(connectedPeer, _) = event else { return false }
                return connectedPeer == peer
            }
            .map { _ in peer }
            .handleEvents(receiveSubscription: { [weak self] _ in
                guard let self else { return }
                browser.invitePeer(peer, to: session, withContext: context, timeout: timeout)
            })
            .eraseToAnyPublisher()
    }

    public func send(_ data: Data, to peer: MCPeerID, reliable: Bool = true) -> Result<Void, Error> {
        Result {
            try session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
        }
    }

    public func sendToAll(_ data: Data, reliable: Bool = true) -> Result<Void, Error> {
        Result {
            try session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        }
    }

    // MARK: - Publisher API (ReactiveConcurrency)

    public var messagesStream: ReactiveConcurrency.Publisher<MultipeerSessionReceivedMessage, Never> {
        DeferredStream { [multicaster = messagesMulticaster] in multicaster.register() }.eraseToPublisher()
    }

    public var connectionsStream: ReactiveConcurrency.Publisher<MultipeerSessionConnectionStatusEvent, Never> {
        DeferredStream { [multicaster = connectionsMulticaster] in multicaster.register() }.eraseToPublisher()
    }

    /// Invites a peer and suspends until it first becomes connected.
    ///
    /// Returns the peer on connection, or `nil` if the session ends before the peer connects.
    /// The continuation is registered before the invite is issued, so the connection event is
    /// never lost to a race with the invite call.
    public func inviteTask(
        peer: MCPeerID,
        browser: MCNearbyServiceBrowser,
        context: Data?,
        timeout: TimeInterval
    ) -> ReactiveConcurrency.Publisher<MCPeerID?, Never> {
        ReactiveConcurrency.Publisher.future { [self] in
            let stream = connectionsMulticaster.register()
            browser.invitePeer(peer, to: session, withContext: context, timeout: timeout)
            for await event in stream {
                if case let .peerConnected(connected, _) = event, connected == peer {
                    return connected
                }
            }
            return nil
        }
    }

    public func sendTask(_ data: Data, to peer: MCPeerID, reliable: Bool = true) -> ReactiveConcurrency.Publisher<Void, Error> {
        ReactiveConcurrency.Publisher.future { [self] in
            Result {
                try session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
            }
        }
    }

    public func sendToAllTask(_ data: Data, reliable: Bool = true) -> ReactiveConcurrency.Publisher<Void, Error> {
        ReactiveConcurrency.Publisher.future { [self] in
            Result {
                try session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
            }
        }
    }

    // MARK: - MCSessionDelegate

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let event: MultipeerSessionConnectionStatusEvent? = switch state {
        case .connected: .peerConnected(peerID, session: session)
        case .connecting: .peerIsConnecting(peerID, session: session)
        case .notConnected: .peerDisconnected(peerID, session: session)
        @unknown default: nil
        }
        guard let event else { return }
        _connections.send(event)
        connectionsMulticaster.send(event)
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let event = MultipeerSessionReceivedMessage.data(data, from: peerID, session: session)
        _messages.send(event)
        messagesMulticaster.send(event)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        let event = MultipeerSessionReceivedMessage.stream(stream, streamName: streamName, from: peerID, session: session)
        _messages.send(event)
        messagesMulticaster.send(event)
    }

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        let event = MultipeerSessionReceivedMessage.didStartReceivingResource(
            resourceName: resourceName,
            from: peerID,
            progress: progress,
            session: session
        )
        _messages.send(event)
        messagesMulticaster.send(event)
    }

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        let event = MultipeerSessionReceivedMessage.didFinishReceivingResource(
            resourceName: resourceName,
            from: peerID,
            localURL: localURL,
            error: error,
            session: session
        )
        _messages.send(event)
        messagesMulticaster.send(event)
    }
}
#endif
