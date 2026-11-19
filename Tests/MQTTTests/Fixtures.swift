// SPDX-License-Identifier: Apache-2.0

import MQTT

// Test-only literals: building these from valid constants cannot fail.
// swiftlint:disable force_unwrapping
func topic(_ value: String) -> TopicName { TopicName(rawValue: value)! }
func filter(_ value: String) -> TopicFilter { TopicFilter(rawValue: value)! }
func id(_ value: UInt16) -> PacketIdentifier { PacketIdentifier(rawValue: value)! }
// swiftlint:enable force_unwrapping

func bytes(_ hex: String) -> [UInt8] {
    let digits = hex.filter(\.isHexDigit)
    return stride(from: 0, to: digits.count, by: 2).compactMap { offset in
        let start = digits.index(digits.startIndex, offsetBy: offset)
        return UInt8(digits[start...digits.index(after: start)], radix: 16)
    }
}

/// One packet of every type, with every optional part filled, valid in MQTT 5.
let everyPacketV5: [Packet] = [
    .connect(Connect(
        protocolVersion: .v5,
        clientIdentifier: "client-1",
        cleanStart: true,
        keepAlive: 60,
        will: Will(
            topic: topic("devices/client-1/status"),
            payload: Array("offline".utf8),
            qos: .atLeastOnce,
            retain: true,
            properties: [.willDelayInterval(5), .contentType("text/plain")]
        ),
        userName: "elegoo",
        password: Array("secret".utf8),
        properties: [.sessionExpiryInterval(120), .receiveMaximum(10), .userProperty(name: "a", value: "b")]
    )),
    .connAck(ConnAck(sessionPresent: true, reasonCode: .success, properties: [.assignedClientIdentifier("x"), .serverKeepAlive(30)])),
    .connAck(ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])),
    .publish(Publish(
        topic: topic("a/b"),
        payload: Array("{\"id\":1}".utf8),
        delivery: .atMostOnce,
        retain: false,
        duplicate: false,
        properties: []
    )),
    .publish(Publish(
        topic: topic("a/b"),
        payload: [],
        delivery: .exactlyOnce(id(7)),
        retain: true,
        duplicate: true,
        properties: [.payloadFormatIndicator(1), .messageExpiryInterval(10), .responseTopic("r"), .correlationData([1, 2])]
    )),
    .pubAck(.success(id(1))),
    .pubAck(Acknowledgement(packetIdentifier: id(2), reasonCode: .noMatchingSubscribers, properties: [])),
    .pubRec(Acknowledgement(packetIdentifier: id(3), reasonCode: .quotaExceeded, properties: [.reasonString("full")])),
    .pubRel(.success(id(4))),
    .pubComp(.success(id(5))),
    .subscribe(Subscribe(
        packetIdentifier: id(10),
        subscriptions: [
            Subscription(filter: filter("elegoo/+/api_status"), options: .qos(.atMostOnce)),
            Subscription(
                filter: filter("$SYS/#"),
                options: SubscriptionOptions(qos: .exactlyOnce, noLocal: true, retainAsPublished: true, retainHandling: .doNotSend)
            ),
        ],
        properties: [.subscriptionIdentifier(300)]
    )),
    .subAck(SubAck(packetIdentifier: id(10), reasonCodes: [.grantedQoS0, .notAuthorized], properties: [])),
    .unsubscribe(Unsubscribe(packetIdentifier: id(11), filters: [filter("a/#"), filter("b")], properties: [])),
    .unsubAck(UnsubAck(packetIdentifier: id(11), reasonCodes: [.success, .noSubscriptionExisted], properties: [])),
    .pingReq,
    .pingResp,
    .disconnect(.normal),
    .disconnect(Disconnect(reasonCode: .serverShuttingDown, properties: [.serverReference("other")])),
    .auth(Auth(reasonCode: .continueAuthentication, properties: [.authenticationMethod("SCRAM"), .authenticationData([9])])),
]

/// One packet of every type expressible in MQTT 3.1.1.
let everyPacketV311: [Packet] = [
    .connect(Connect(
        protocolVersion: .v3_1_1,
        clientIdentifier: "client-1",
        cleanStart: false,
        keepAlive: 0,
        will: Will(topic: topic("w"), payload: [1], qos: .exactlyOnce, retain: false, properties: []),
        userName: "elegoo",
        password: Array("secret".utf8),
        properties: []
    )),
    .connAck(ConnAck(sessionPresent: false, reasonCode: .badUserNameOrPassword, properties: [])),
    .publish(Publish(topic: topic("a"), payload: [0xFF], delivery: .atLeastOnce(id(9)), retain: false, duplicate: false, properties: [])),
    .pubAck(.success(id(1))),
    .pubRec(.success(id(2))),
    .pubRel(.success(id(3))),
    .pubComp(.success(id(4))),
    .subscribe(Subscribe(
        packetIdentifier: id(5),
        subscriptions: [Subscription(filter: filter("#"), options: .qos(.atLeastOnce))],
        properties: []
    )),
    .subAck(SubAck(packetIdentifier: id(5), reasonCodes: [.grantedQoS1, .unspecifiedError], properties: [])),
    .unsubscribe(Unsubscribe(packetIdentifier: id(6), filters: [filter("#")], properties: [])),
    .unsubAck(UnsubAck(packetIdentifier: id(6), reasonCodes: [], properties: [])),
    .pingReq,
    .pingResp,
    .disconnect(.normal),
]
