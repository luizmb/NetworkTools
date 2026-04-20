import Foundation

/// Sentinel type for route parameters that require no decoding.
public struct Empty: Codable, Sendable {
    public static let value = Empty()
    public init() {}
    public init(from decoder: any Decoder) throws { _ = try decoder.container(keyedBy: CodingKeys.self) }
    public func encode(to encoder: any Encoder) throws { _ = encoder.container(keyedBy: CodingKeys.self) }
    private enum CodingKeys: CodingKey {}
}
