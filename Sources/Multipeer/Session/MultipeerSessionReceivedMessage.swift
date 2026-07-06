// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Foundation
@preconcurrency import MultipeerConnectivity

/// Inbound traffic events for an `MCSession`: data, byte streams, and resource transfers.
public enum MultipeerSessionReceivedMessage: @unchecked Sendable {
    case data(Data, from: MCPeerID, session: MCSession)
    case stream(InputStream, streamName: String, from: MCPeerID, session: MCSession)
    case didStartReceivingResource(resourceName: String, from: MCPeerID, progress: Progress, session: MCSession)
    case didFinishReceivingResource(resourceName: String, from: MCPeerID, localURL: URL?, error: Error?, session: MCSession)
}
#endif
