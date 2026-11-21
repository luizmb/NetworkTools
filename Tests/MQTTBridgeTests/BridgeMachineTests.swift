// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTBridge
import MQTTClient
import Testing

// swiftlint:disable force_unwrapping
private func topic(_ value: String) -> TopicName { TopicName(rawValue: value)! }
private func filter(_ value: String) -> TopicFilter { TopicFilter(rawValue: value)! }
// swiftlint:enable force_unwrapping

private let connected = ClientEvent.connected(ConnAck(sessionPresent: false, reasonCode: .success, properties: []))

private func message(_ name: String, _ payload: String = "x", qos: Delivery = .atMostOnce) -> ClientEvent {
    .message(Publish(topic: topic(name), payload: Array(payload.utf8), delivery: qos, retain: false, duplicate: false, properties: []))
}

private func run(_ inputs: [(BridgeSide, ClientEvent)], _ state: BridgeState) -> ([BridgeOutput], BridgeState) {
    inputs.reduce(([BridgeOutput](), state)) { acc, input in
        let (outputs, next) = BridgeMachine.step(input.0, input.1).runStateful(acc.1)
        return (acc.0 + outputs, next)
    }
}

private func requests(_ outputs: [BridgeOutput], to side: BridgeSide) -> [ClientRequest] {
    outputs.compactMap { output in
        guard case let .request(target, request) = output, target == side else { return nil }
        return request
    }
}

private let printerRule = BridgeRule(
    filter: filter("printer/#"),
    direction: .outbound,
    qos: .atLeastOnce,
    localPrefix: "",
    remotePrefix: "home/"
)

@Suite struct BridgeMachineTests {
    private let v5 = BridgeState.initial(rules: [printerRule], local: .v5, remote: .v5)

    @Test func subscribesWhereMessagesComeFromWithNoLocal() {
        let (outputs, _) = run([(.local, connected), (.remote, connected)], v5)
        let options = SubscriptionOptions(qos: .atLeastOnce, noLocal: true, retainAsPublished: true, retainHandling: .sendOnSubscribe)
        let expected = ClientRequest.subscribe([Subscription(filter: filter("printer/#"), options: options)], properties: [])
        #expect(requests(outputs, to: .local) == [expected])
        #expect(requests(outputs, to: .remote).isEmpty)
    }

    @Test func subscribesOnlyOnTheFirstConnection() {
        let (outputs, _) = run([(.local, connected), (.local, connected)], v5)
        #expect(requests(outputs, to: .local).count == 1)
    }

    @Test func forwardsWithThePrefixesApplied() {
        let (outputs, _) = run([(.local, message("printer/status", "42", qos: .exactlyOnce(PacketIdentifier.first)))], v5)
        #expect(requests(outputs, to: .remote) == [
            .publish(OutgoingMessage(
                topic: topic("home/printer/status"),
                payload: Array("42".utf8),
                qos: .atLeastOnce,
                retain: false,
                properties: []
            )),
        ])
    }

    @Test func ignoresTopicsOutsideTheRules() {
        #expect(requests(run([(.local, message("kitchen/oven"))], v5).0, to: .remote).isEmpty)
    }

    @Test func ignoresTheWrongDirection() {
        #expect(requests(run([(.remote, message("home/printer/status"))], v5).0, to: .local).isEmpty)
    }

    @Test func inboundRulesStripTheRemotePrefix() {
        let rule = BridgeRule(filter: filter("cmd/+"), direction: .inbound, qos: .atMostOnce, localPrefix: "local/", remotePrefix: "cloud/")
        let (outputs, _) = run([(.remote, message("cloud/cmd/pause"))], .initial(rules: [rule], local: .v5, remote: .v5))
        #expect(requests(outputs, to: .local).map { request -> String in
            guard case let .publish(message) = request else { return "" }
            return message.topic.rawValue
        } == ["local/cmd/pause"])
    }

    @Test func dropsItsOwnEchoOn311() {
        let both = BridgeRule(filter: filter("sync/#"), direction: .both, qos: .atMostOnce, localPrefix: "", remotePrefix: "")
        let state = BridgeState.initial(rules: [both], local: .v3_1_1, remote: .v3_1_1)
        let (outputs, _) = run(
            [(.local, message("sync/a", "1")), (.remote, message("sync/a", "1")), (.remote, message("sync/a", "2"))],
            state
        )
        #expect(requests(outputs, to: .remote).count == 1)
        #expect(requests(outputs, to: .local).count == 1)
    }
}
