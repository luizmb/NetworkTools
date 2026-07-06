// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Foundation
@preconcurrency import MultipeerConnectivity

/// Connection lifecycle events for peers in an `MCSession`.
public enum MultipeerSessionConnectionStatusEvent: @unchecked Sendable {
    case peerIsConnecting(MCPeerID, session: MCSession)
    case peerConnected(MCPeerID, session: MCSession)
    case peerDisconnected(MCPeerID, session: MCSession)
}
#endif
