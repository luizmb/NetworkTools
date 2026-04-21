#if canImport(Combine)
import Combine
import Foundation
import FP

public extension AnyPublisher where Output: Encodable, Failure == EncodingError {
    func encode(using encoder: EncoderResult<Output>) -> AnyPublisher<Data, EncodingError> {
        flatMap { value in
             encoder(value).publisher.eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func encode(using factory: EncoderResultFactory) -> AnyPublisher<Data, EncodingError> {
        encode(using: factory.encoderResult(for: Output.self))
    }
}

public extension AnyPublisher where Output: Encodable {
    func encode(using encoder: EncoderResult<Output>, mapError errorTransform: @escaping (EncodingError) -> Failure) -> AnyPublisher<Data, Failure> {
        flatMap { value in
             encoder(value).publisher.mapError(errorTransform).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func encode(using factory: EncoderResultFactory, mapError errorTransform: @escaping (EncodingError) -> Failure) -> AnyPublisher<Data, Failure> {
        encode(using: factory.encoderResult(for: Output.self), mapError: errorTransform)
    }
}
#endif
