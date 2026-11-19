// SPDX-License-Identifier: Apache-2.0

import Foundation
import MQTT
import MQTTWebSocket
import ReactiveConcurrency
import Testing
import WebSocketClient

/// Records what the transport sends. Test-only shared state behind a lock.
private final class SentFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [WebSocketMessage] = []

    var all: [WebSocketMessage] { lock.withLock { frames } }

    func append(_ frame: WebSocketMessage) {
        lock.withLock { frames.append(frame) }
    }
}

private func socket(receiving messages: [WebSocketMessage], recording sent: SentFrames) -> WebSocketConnection {
    WebSocketConnection(
        receive: messages.publisher.setFailureType(to: Error.self),
        send: { frame in
            sent.append(frame)
            return .just(())
        },
        ping: .just(()),
        cancel: {}
    )
}

@Suite struct WebSocketTransportTests {
    @Test func binaryFramesBecomeBytes() async {
        let sent = SentFrames()
        let transport = Transport.webSocket {
            .just(socket(receiving: [.data(Data([0x20, 0x02])), .data(Data([0x00, 0x00]))], recording: sent))
        }
        let chunks = await transport.connect()
            .flatMap(maxPublishers: 1, \.receive)
            .collect()
            .firstResultTask()
            .run()
        #expect(chunks == .success([[0x20, 0x02], [0x00, 0x00]]))
    }

    @Test func textFramesAreRejected() async {
        let sent = SentFrames()
        let transport = Transport.webSocket { .just(socket(receiving: [.text("hi")], recording: sent)) }
        let chunks = await transport.connect()
            .flatMap(maxPublishers: 1, \.receive)
            .collect()
            .firstResultTask()
            .run()
        #expect(chunks == .failure(.unexpectedData("hi")))
    }

    @Test func bytesAreSentAsBinaryFrames() async {
        let sent = SentFrames()
        let transport = Transport.webSocket { .just(socket(receiving: [], recording: sent)) }
        _ = await transport.connect()
            .flatMap(maxPublishers: 1) { $0.send([0xC0, 0x00]) }
            .firstResultTask()
            .run()
        #expect(sent.all == [.data(Data([0xC0, 0x00]))])
    }
}
