#if canImport(Combine)
import Combine
import Foundation
import FP

public extension AnyPublisher where Output: Encodable, Failure == EncodingError {
    func encode(using factory: DataEncoderFactory) -> AnyPublisher<Data, EncodingError> {
        encode(using: factory.dataEncoder(for: Output.self))
    }
}

public extension AnyPublisher where Output: Encodable {
    func encode(using encoder: Convert<Output, Data, Failure>) -> AnyPublisher<Data, Failure> {
        flatMap { value in
             encoder(value).publisher.eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func encode(
        using factory: DataEncoderFactory,
        mapError errorTransform: @escaping (EncodingError) -> Failure
    ) -> AnyPublisher<Data, Failure> {
        encode(using: factory.dataEncoder(for: Output.self).mapError(errorTransform))
    }

    func encode(
        using encoder: Convert<Output,
        Data, EncodingError>,
        mapError errorTransform: @escaping (EncodingError) -> Failure
    ) -> AnyPublisher<Data, Failure> {
        encode(using: encoder.mapError(errorTransform))
    }
}
#endif
