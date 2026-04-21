#if canImport(Combine)
import Combine
import Foundation
import FP

public extension AnyPublisher where Output: Decodable, Failure == DecodingError {
    static func decoding(_ data: Data, using decoder: DecoderResult<Output>) -> Self {
        decoder(data).publisher.eraseToAnyPublisher()
    }

    static func decoding(_ data: Data, using factory: DecoderResultFactory, type: Output.Type = Output.self) -> Self {
        decoding(data, using: factory.decoderResult(for: Output.self))
    }
}

public extension AnyPublisher where Output == Data, Failure == EncodingError {
    static func encoding<E: Encodable>(_ value: E, using encoder: EncoderResult<E>) -> Self {
        encoder(value).publisher.eraseToAnyPublisher()
    }

    static func encoding<E: Encodable>(_ value: E, using factory: EncoderResultFactory) -> Self {
        encoding(value, using: factory.encoderResult(for: E.self))
    }
}
#endif
