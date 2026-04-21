#if canImport(Combine)
import Combine
import Core
import Foundation

// MARK: - Decoding

public extension RequestPublisher where A == Data {
    /// Decodes the raw `Data` output using the provided `DecoderResult` function.
    func decode<D: Decodable>(using decoder: DecoderResult<D>) -> RequestPublisher<D> {
        RequestPublisher<D> { request in
            run(request).flatMap { data in
                AnyPublisher.decoding(data, using: decoder).mapError(HTTPError.decoding)
            }
            .eraseToAnyPublisher()
        }
    }

    /// Decodes the raw `Data` output using the provided `DecoderResultFactory`.
    func decode<D: Decodable>(using factory: DecoderResultFactory, type: D.Type = D.self) -> RequestPublisher<D> {
        decode(using: factory.decoderResult(for: D.self))
    }
}
#endif
