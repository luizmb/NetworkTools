// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum HTTPError: Error, Sendable {
    case network(Error)
    case badStatus(Int, Data)
    case decoding(Error)
}

extension HTTPError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .network(e): "Network error: \(e.localizedDescription)"
        case let .badStatus(c, _): "HTTP \(c)"
        case let .decoding(e): "Decoding error: \(e.localizedDescription)"
        }
    }
}
