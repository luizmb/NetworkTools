// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
import FP

/// A consume-once source of recorded exchanges — the state behind the replay decorator.
///
/// Each recorded exchange is served **at most once**, in file order, so replaying a captured session
/// where the same endpoint returns different responses over time works correctly. Mutation of the
/// per-exchange cursor is serialized by the actor.
public actor RequestPlayback {
    private let exchanges: [RecordedExchange]
    private var consumed: Set<Int> = []

    public init(exchanges: [RecordedExchange]) {
        self.exchanges = exchanges
    }

    /// Loads recordings from disk through an injected reader + any `DataDecoderFactory`.
    /// Returns `nil` if the file can't be read or decoded.
    public static func load(
        url: URL,
        read: BinaryReader = BinaryIO.read,
        decoder: some DataDecoderFactory & Sendable
    ) -> RequestPlayback? {
        let decode = decoder.dataDecoder(for: [RecordedExchange].self)
        guard
            case let .success(data) = read(url),
            case let .success(exchanges) = decode.run(data)
        else { return nil }
        return RequestPlayback(exchanges: exchanges)
    }

    /// Returns the first not-yet-consumed exchange matching `request`, marking it consumed.
    public func consume(
        for request: URLRequest,
        matching: @Sendable (URLRequest, RecordedExchange) -> Bool
    ) -> RecordedExchange? {
        for index in exchanges.indices where !consumed.contains(index) && matching(request, exchanges[index]) {
            consumed.insert(index)
            return exchanges[index]
        }
        return nil
    }

    /// How many exchanges remain unconsumed.
    public var remaining: Int { exchanges.count - consumed.count }
}

// MARK: - Default matching

public extension RecordedExchange {
    /// Default replay matcher: same HTTP method and absolute URL (query included).
    static let matchesMethodAndURL: @Sendable (URLRequest, RecordedExchange) -> Bool = { request, exchange in
        (request.httpMethod ?? "GET") == exchange.method && request.url?.absoluteString == exchange.url
    }
}
