#if canImport(Combine)
import Combine
import Foundation

// MARK: - Decoding

public extension RequestPublisher where A == Data {

    /// Decodes the raw `Data` output using the provided `DecoderResult` function.
    func decode<D: Decodable>(_ type: D.Type, decoder: @escaping (Data) -> Result<D, DecodingError>) -> RequestPublisher<D> {
        RequestPublisher<D> { request in
            run(request).flatMap { data in
                decoder(data)
                    .mapError(HTTPError.decoding)
                    .publisher
            }.eraseToAnyPublisher()
        }
    }
}
#endif
