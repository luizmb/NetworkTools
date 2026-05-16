// MCNearbyServiceBrowserDelegate hands back discoveryInfo as [String: String]? mirroring the
// underlying Bonjour TXT record (nil — no TXT — vs [:] — empty TXT — differ semantically), so
// the optional collection is kept intentionally.
// swiftlint:disable discouraged_optional_collection
#if canImport(MultipeerConnectivity)
import Foundation
@preconcurrency import MultipeerConnectivity

/// Events emitted by a Multipeer browser.
public enum MultipeerBrowserEvent: @unchecked Sendable {
    case foundPeer(peerID: MCPeerID, info: [String: String]?, browser: MCNearbyServiceBrowser)
    case lostPeer(peerID: MCPeerID)
}
#endif
// swiftlint:enable discouraged_optional_collection
