// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Foundation
import FP
@preconcurrency import MultipeerConnectivity
import ReactiveConcurrency

/// A Multipeer session exposing its messages, connection events and invitations as ReactiveConcurrency
/// `Publisher`s.
///
/// `messagesStream` and `connectionsStream` are **multicast**: the underlying `MCSessionDelegate` is a
/// single, always-on source, so both are backed by a `PassthroughSubject` — every subscriber receives
/// every event from the moment it subscribes.
public class MultipeerSession: NSObject, MCSessionDelegate, @unchecked Sendable {
    public let session: MCSession

    private let messagesSubject = PassthroughSubject<MultipeerSessionReceivedMessage, Never>()
    private let connectionsSubject = PassthroughSubject<MultipeerSessionConnectionStatusEvent, Never>()

    public init(myselfAsPeer: MCPeerID) {
        session = MCSession(peer: myselfAsPeer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    deinit {
        messagesSubject.send(completion: .finished)
        connectionsSubject.send(completion: .finished)
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

    // MARK: - Publisher API (multicast)

    public var messagesStream: Publisher<MultipeerSessionReceivedMessage, Never> {
        messagesSubject.eraseToPublisher()
    }

    public var connectionsStream: Publisher<MultipeerSessionConnectionStatusEvent, Never> {
        connectionsSubject.eraseToPublisher()
    }

    /// Invites a peer and suspends until it first becomes connected.
    ///
    /// Returns the peer on connection, or `nil` if the session ends before the peer connects.
    /// The invite is issued as the subscription starts; because a Multipeer connection requires a
    /// network round-trip, the `.peerConnected` event always arrives well after the subscription is
    /// established.
    public func inviteTask(
        peer: MCPeerID,
        browser: MCNearbyServiceBrowser,
        context: Data?,
        timeout: TimeInterval
    ) -> Publisher<MCPeerID?, Never> {
        Publisher.future { [self] in
            let events = connectionsSubject.eraseToPublisher()
            browser.invitePeer(peer, to: session, withContext: context, timeout: timeout)
            for await event in events.values {
                if case let .peerConnected(connected, _) = event, connected == peer {
                    return connected
                }
            }
            return nil
        }
    }

    public func sendTask(_ data: Data, to peer: MCPeerID, reliable: Bool = true) -> Publisher<Void, Error> {
        Publisher.future { [self] in
            Result {
                try session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
            }
        }
    }

    public func sendToAllTask(_ data: Data, reliable: Bool = true) -> Publisher<Void, Error> {
        Publisher.future { [self] in
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
        connectionsSubject.send(event)
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        messagesSubject.send(.data(data, from: peerID, session: session))
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        messagesSubject.send(.stream(stream, streamName: streamName, from: peerID, session: session))
    }

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        messagesSubject.send(.didStartReceivingResource(
            resourceName: resourceName,
            from: peerID,
            progress: progress,
            session: session
        ))
    }

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        messagesSubject.send(.didFinishReceivingResource(
            resourceName: resourceName,
            from: peerID,
            localURL: localURL,
            error: error,
            session: session
        ))
    }
}

#endif
