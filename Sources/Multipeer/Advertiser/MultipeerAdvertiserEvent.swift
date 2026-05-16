#if canImport(MultipeerConnectivity)
import Foundation
@preconcurrency import MultipeerConnectivity

/// Events emitted by a Multipeer advertiser.
///
/// Marked `@unchecked Sendable` because the payload carries Apple framework reference types
/// (`MCPeerID`, `MCSession`) and a non-Sendable invitation handler closure. Treat the values
/// as immutable in transit and call the handler exactly once.
public enum MultipeerAdvertiserEvent: @unchecked Sendable {
    case didReceiveInvitationFromPeer(MCPeerID, context: Data?, handler: (Bool, MCSession?) -> Void)
}
#endif
