import Foundation

public enum HTTPError: Error, Sendable {
    case network(Error)
    case badStatus(Int, Data)
    case decoding(Error)
}

extension HTTPError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .network(let e):      "Network error: \(e.localizedDescription)"
        case .badStatus(let c, _): "HTTP \(c)"
        case .decoding(let e):     "Decoding error: \(e.localizedDescription)"
        }
    }
}
