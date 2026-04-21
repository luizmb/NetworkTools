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
                decoder(data)
                    .mapError(HTTPError.decoding)
                    .publisher
            }
            .eraseToAnyPublisher()
        }
    }

    /// Decodes the raw `Data` output using the provided `DecoderResultFactory`.
    func decode<D: Decodable>(using decoder: DecoderResultFactory, type: D.Type = D.self) -> RequestPublisher<D> {
        decode(using: decoder.decoderResult(for: D.self))
    }
}
#endif
