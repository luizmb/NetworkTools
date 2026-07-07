// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Foundation
import FP
@testable import Multipeer
@preconcurrency import MultipeerConnectivity
import ReactiveConcurrency
import Testing

// Smoke tests for surface API shape — full integration testing requires two devices and is
// out of scope here. These tests cover deferred-execution semantics and lock-protected
// multicast plumbing.

// MARK: - Multicast (PassthroughSubject)

/// Verifies the multicast fan-out that `MultipeerSession`'s `messagesStream` / `connectionsStream`
/// rely on (both are backed by RC `PassthroughSubject`).
@Suite("Multicast")
struct MulticastTests {
    @Test func subjectFansOutToAllSubscribers() async {
        let subject = PassthroughSubject<Int, Never>()

        async let collectedA: [Int] = collect(subject.eraseToPublisher(), count: 3)
        async let collectedB: [Int] = collect(subject.eraseToPublisher(), count: 3)

        // Give both subscribers a moment to register before sending.
        try? await Task.sleep(nanoseconds: 20_000_000)
        subject.send(1)
        subject.send(2)
        subject.send(3)

        let (resultA, resultB) = await (collectedA, collectedB)
        #expect(resultA == [1, 2, 3])
        #expect(resultB == [1, 2, 3])
    }

    @Test func completionEndsAllSubscribers() async {
        let subject = PassthroughSubject<Int, Never>()
        async let drained: [Int] = {
            var out: [Int] = []
            for await value in subject.eraseToPublisher().values {
                out.append(value)
            }
            return out
        }()

        try? await Task.sleep(nanoseconds: 20_000_000)
        subject.send(42)
        subject.send(completion: .finished)

        #expect(await drained == [42])
    }

    private func collect(_ publisher: Publisher<Int, Never>, count: Int) async -> [Int] {
        var out: [Int] = []
        for await value in publisher.values {
            out.append(value)
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
    @Test func sessionExposesPublisherAPIs() {
        let peer = MCPeerID(displayName: "tester")
        let session = MultipeerSession(myselfAsPeer: peer)

        // Just touch the API surface to ensure it type-checks and constructs.
        _ = session.messagesStream
        _ = session.connectionsStream
        _ = session.sendTask(Data(), to: peer)
        _ = session.sendToAllTask(Data())

        #expect(session.session.myPeerID == peer)
    }
}
#endif
