// SPDX-License-Identifier: Apache-2.0

import MQTT
import Testing

@Suite struct TopicTests {
    static let matching: [(String, String, Bool)] = [
        ("sport/tennis/player1", "sport/tennis/player1", true),
        ("sport/tennis/player1/#", "sport/tennis/player1", true),
        ("sport/tennis/player1/#", "sport/tennis/player1/ranking", true),
        ("sport/tennis/player1/#", "sport/tennis/player1/score/wimbledon", true),
        ("sport/#", "sport", true),
        ("#", "anything/at/all", true),
        ("sport/tennis/+", "sport/tennis/player1", true),
        ("sport/tennis/+", "sport/tennis/player1/ranking", false),
        ("sport/+", "sport", false),
        ("sport/+", "sport/", true),
        ("+/+", "/finance", true),
        ("/+", "/finance", true),
        ("+", "/finance", false),
        ("elegoo/+/api_status", "elegoo/SERIAL/api_status", true),
        ("elegoo/+/api_status", "elegoo/SERIAL/c1/api_status", false),
        ("#", "$SYS/broker/version", false),
        ("+/broker/version", "$SYS/broker/version", false),
        ("$SYS/#", "$SYS/broker/version", true),
        ("$SYS/+/version", "$SYS/broker/version", true),
        ("a/b", "a/c", false),
    ]

    @Test(arguments: matching)
    func matches(filterValue: String, topicValue: String, expected: Bool) {
        #expect(filter(filterValue).matches(topic(topicValue)) == expected)
    }

    @Test(arguments: ["sport/tennis#", "sport/#/ranking", "sport+", "", "a/b#", "\u{0000}"])
    func invalidFilters(value: String) {
        #expect(TopicFilter(rawValue: value) == nil)
    }

    @Test(arguments: ["a/+", "#", "a/#/b", "\u{0000}"])
    func invalidNames(value: String) {
        #expect(TopicName(rawValue: value) == nil)
    }

    @Test func packetIdentifiersWrapAndSkipZero() {
        #expect(PacketIdentifier(rawValue: 0) == nil)
        #expect(id(UInt16.max).next == .first)
        #expect(id(41).next == id(42))
    }
}
