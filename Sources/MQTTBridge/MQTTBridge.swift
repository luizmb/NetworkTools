// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import ReactiveConcurrency

/// The worlds of a bridge's two client sessions.
public struct BridgeWorld: Sendable {
    /// Connects to the local broker.
    public let local: ClientWorld
    /// Connects to the remote broker.
    public let remote: ClientWorld

    /// Creates a bridge world.
    public init(local: ClientWorld, remote: ClientWorld) {
        self.local = local
        self.remote = remote
    }
}

/// An MQTT bridge: a client session to each of two brokers, forwarding messages between them by
/// ``BridgeRule``s.
///
/// Each side is an ordinary ``MQTTClient`` session, so it reconnects, resumes and re-subscribes
/// according to its own ``ClientOptions``. Use ``ReconnectPolicy`` on both sides for a long-lived
/// bridge. Either broker can be any MQTT broker — including an `MQTTBroker` on loopback.
///
/// ```swift
/// // Everything under `printer/` locally appears under `home/printer/` remotely.
/// let rules = [BridgeRule(filter: printerTopics, direction: .outbound, qos: .atLeastOnce, localPrefix: "", remotePrefix: "home/")]
/// let bridge = MQTTBridge.run(rules: rules, local: localOptions, remote: remoteOptions).runReader(world)
/// ```
public enum MQTTBridge {
    /// Builds a bridge.
    /// - Parameters:
    ///   - rules: What to forward, and which way.
    ///   - local: How to connect to the local broker.
    ///   - remote: How to connect to the remote broker.
    /// - Returns: The bridge, waiting for its world.
    public static func run(rules: [BridgeRule], local: ClientOptions, remote: ClientOptions) -> Reader<BridgeWorld, Publisher<
        BridgeEvent,
        BridgeError
    >> {
        Reader { world in
            // `just(()).flatMap` defers construction: every subscription gets its own request streams.
            Publisher<Void, BridgeError>.just(()).flatMap(maxPublishers: 1) { _ in
                wire(rules: rules, local: local, remote: remote, world: world)
            }
        }
    }

    private struct Fold: Sendable {
        var state: BridgeState
        var outputs: [BridgeOutput]
    }

    private static func wire(
        rules: [BridgeRule],
        local: ClientOptions,
        remote: ClientOptions,
        world: BridgeWorld
    ) -> Publisher<BridgeEvent, BridgeError> {
        let (localRequests, toLocal) = AsyncStream<ClientRequest>.makeStream()
        let (remoteRequests, toRemote) = AsyncStream<ClientRequest>.makeStream()
        let localEvents = MQTTClient.session(local, requests: DeferredStream { localRequests }.eraseToPublisher())
            .runReader(world.local)
            .map { (BridgeSide.local, $0) }
            .mapError { BridgeError.session(.local, $0) }
        let remoteEvents = MQTTClient.session(remote, requests: DeferredStream { remoteRequests }.eraseToPublisher())
            .runReader(world.remote)
            .map { (BridgeSide.remote, $0) }
            .mapError { BridgeError.session(.remote, $0) }
        let initial = BridgeState.initial(rules: rules, local: local.version, remote: remote.version)
        return localEvents.merge(with: remoteEvents)
            .scan(Fold(state: initial, outputs: [])) { fold, sideEvent in
                let (outputs, state) = BridgeMachine.step(sideEvent.0, sideEvent.1).runStateful(fold.state)
                return Fold(state: state, outputs: outputs)
            }
            .flatMap(maxPublishers: 1) { fold in
                Publisher<BridgeEvent, BridgeError>.empty().append(fold.outputs.compactMap { output -> BridgeEvent? in
                    switch output {
                    case let .request(.local, request):
                        toLocal.yield(request)
                        return nil
                    case let .request(.remote, request):
                        toRemote.yield(request)
                        return nil
                    case let .emit(event):
                        return event
                    }
                })
            }
    }
}
