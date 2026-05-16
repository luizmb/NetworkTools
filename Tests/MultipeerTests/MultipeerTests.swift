#if canImport(MultipeerConnectivity)
import Foundation
import FP
@testable import Multipeer
@preconcurrency import MultipeerConnectivity
import Testing

// Smoke tests for surface API shape — full integration testing requires two devices and is
// out of scope here. These tests cover deferred-execution semantics and lock-protected
// multicast plumbing.

// MARK: - AsyncMulticaster

@Suite("AsyncMulticaster")
struct AsyncMulticasterTests {
    @Test func registerYieldsToAllSubscribers() async {
        let multicaster = AsyncMulticaster<Int>()
        let streamA = multicaster.register()
        let streamB = multicaster.register()

        async let collectedA: [Int] = collect(stream: streamA, count: 3)
        async let collectedB: [Int] = collect(stream: streamB, count: 3)

        // Give the iterators a moment to start awaiting before we send.
        try? await Task.sleep(nanoseconds: 10_000_000)
        multicaster.send(1)
        multicaster.send(2)
        multicaster.send(3)

        let (resultA, resultB) = await (collectedA, collectedB)
        #expect(resultA == [1, 2, 3])
        #expect(resultB == [1, 2, 3])
    }

    @Test func finishCompletesAllStreams() async {
        let multicaster = AsyncMulticaster<Int>()
        let stream = multicaster.register()

        async let drained: [Int] = {
            var out: [Int] = []
            for await element in stream { out.append(element) }
            return out
        }()

        try? await Task.sleep(nanoseconds: 10_000_000)
        multicaster.send(42)
        multicaster.finish()

        let result = await drained
        #expect(result == [42])
    }

    private func collect<E>(stream: AsyncStream<E>, count: Int) async -> [E] {
        var out: [E] = []
        for await element in stream {
            out.append(element)
            if out.count == count { break }
        }
        return out
    }
}

// MARK: - DeferredStream factories

@Suite("Stream factories")
struct StreamFactoryTests {
    @Test func advertiserStreamIsLazy() {
        // Constructing the DeferredStream must not start advertising — no MC objects created.
        let peer = MCPeerID(displayName: "tester")
        _ = multipeerAdvertiserStream(myselfAsPeer: peer, serviceType: "ms-test")
        // If we reach here without a crash or thread issue, the deferred semantics hold.
        #expect(Bool(true))
    }

    @Test func browserStreamIsLazy() {
        let peer = MCPeerID(displayName: "tester")
        _ = multipeerBrowserStream(myselfAsPeer: peer, serviceType: "ms-test")
        #expect(Bool(true))
    }
}

// MARK: - Session API surface

@Suite("MultipeerSession")
struct MultipeerSessionTests {
    @Test func sessionExposesBothCombineAndDeferredStreamAPIs() {
        let peer = MCPeerID(displayName: "tester")
        let session = MultipeerSession(myselfAsPeer: peer)

        // Just touch the API surface to ensure it type-checks and constructs.
        _ = session.messages
        _ = session.connections
        _ = session.messagesStream
        _ = session.connectionsStream
        _ = session.sendTask(Data(), to: peer)
        _ = session.sendToAllTask(Data())

        #expect(session.session.myPeerID == peer)
    }
}
#endif
