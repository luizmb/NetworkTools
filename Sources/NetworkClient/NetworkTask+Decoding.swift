import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP

// MARK: - Decoding

private func _decode<D: Decodable & Sendable>(_ data: Data, using decoder: DataDecoder<D>) -> NetworkTask<D> {
    ZIO { _ in DeferredTask { decoder.run(data).mapError(HTTPError.decoding) } }
}

public extension ZIO where Env == URLRequest, Success == Data, Failure == HTTPError {
    /// Decodes the raw `Data` output using the provided `DataDecoder`.
    func decode<D: Decodable & Sendable>(using decoder: DataDecoder<D>) -> NetworkTask<D> {
        flatMap { _decode($0, using: decoder) }
    }

    /// Decodes the raw `Data` output using the provided `DataDecoderFactory`.
    func decode<D: Decodable & Sendable>(
        using factory: DataDecoderFactory,
        type: D.Type = D.self
    ) -> NetworkTask<D> {
        decode(using: factory.dataDecoder(for: D.self))
    }
}
