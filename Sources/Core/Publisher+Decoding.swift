#if canImport(Combine)
import Combine
import Foundation
import FP

public extension AnyPublisher where Output: Decodable, Failure == DecodingError {
    static func decoding(_ data: Data, using factory: DataDecoderFactory, type: Output.Type = Output.self) -> Self {
        decoding(data, using: factory.dataDecoder(for: Output.self))
    }
}

public extension AnyPublisher where Output: Decodable {
    static func decoding(_ data: Data, using decoder: Convert<Data, Output, Failure>) -> Self {
        decoder(data).publisher.eraseToAnyPublisher()
    }

    static func decoding(_ data: Data, using factory: DataDecoderFactory, mapError errorTransform: @escaping (DecodingError) -> Failure, type: Output.Type = Output.self) -> Self {
        decoding(data, using: factory.dataDecoder(for: Output.self).mapError(errorTransform))
    }
}

#endif
