// SPDX-License-Identifier: Apache-2.0

/// The topic an application message is published to, e.g. `elegoo/F0130/api_status`.
///
/// A topic name never contains the wildcards `+` or `#`, nor the null character, and its
/// UTF-8 encoding fits in 65 535 bytes. It may be empty only in MQTT 5, where a PUBLISH can
/// carry a Topic Alias instead of the name; the codec rejects empty names in 3.1.1.
public struct TopicName: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The topic as written.
    public let rawValue: String

    /// Validates a topic name.
    /// - Parameter rawValue: The candidate name.
    public init?(rawValue: String) {
        guard TopicName.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// The topic levels, split on `/` (empty levels are kept: `a//b` has three levels).
    public var levels: [Substring] {
        rawValue.split(separator: "/", omittingEmptySubsequences: false)
    }

    /// The topic as written.
    public var description: String { rawValue }

    static func isValid(_ value: String) -> Bool {
        value.utf8.count <= Int(UInt16.max)
            && !value.contains { $0 == "+" || $0 == "#" || $0 == "\u{0000}" }
    }
}

/// A subscription pattern, e.g. `elegoo/+/api_status` or `$SYS/#`.
///
/// `+` matches exactly one level and must fill its level; `#` matches any number of levels
/// (including none) and must be the last level on its own. Filters are non-empty.
public struct TopicFilter: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The filter as written.
    public let rawValue: String

    /// Validates a topic filter.
    /// - Parameter rawValue: The candidate filter.
    public init?(rawValue: String) {
        guard TopicFilter.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// The filter levels, split on `/`.
    public var levels: [Substring] {
        rawValue.split(separator: "/", omittingEmptySubsequences: false)
    }

    /// The filter as written.
    public var description: String { rawValue }

    /// Whether `topic` is matched by this filter, following the MQTT rules, including that a
    /// filter starting with a wildcard does not match topics starting with `$`.
    /// - Parameter topic: The topic of a published message.
    /// - Returns: `true` when a subscription with this filter receives the message.
    public func matches(_ topic: TopicName) -> Bool {
        let filterLevels = levels
        let topicLevels = topic.levels
        let systemTopic = topic.rawValue.hasPrefix("$")
        let wildcardFirst = filterLevels.first == "+" || filterLevels.first == "#"
        return !(systemTopic && wildcardFirst) && TopicFilter.match(filterLevels[...], topicLevels[...])
    }

    static func isValid(_ value: String) -> Bool {
        let levels = value.split(separator: "/", omittingEmptySubsequences: false)
        return !value.isEmpty
            && value.utf8.count <= Int(UInt16.max)
            && !value.contains("\u{0000}")
            && levels.enumerated().allSatisfy { index, level in
                switch level {
                case "#": index == levels.count - 1
                case "+": true
                default: !level.contains("#") && !level.contains("+")
                }
            }
    }

    private static func match(_ filter: ArraySlice<Substring>, _ topic: ArraySlice<Substring>) -> Bool {
        switch (filter.first, topic.first) {
        case (.none, .none): true
        case ("#", _): true
        case (.none, .some), (.some, .none): false
        case let (.some(level), .some(name)):
            (level == "+" || level == name) && match(filter.dropFirst(), topic.dropFirst())
        }
    }
}
