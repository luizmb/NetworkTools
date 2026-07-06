// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency
import ReactiveConcurrencyTransformers

// MARK: - Decoding

private func _decode<D: Decodable & Sendable>(_ data: Data, using decoder: DataDecoder<D>) -> NetworkTask<D> {
    Reader { _ in Publisher.future { decoder.run(data).mapError(HTTPError.decoding) } }
}

public extension Reader where Environment == URLRequest, Output == Publisher<Data, HTTPError> {
    /// Decodes the raw `Data` output using the provided `DataDecoder`.
    func decode<D: Decodable & Sendable>(using decoder: DataDecoder<D>) -> NetworkTask<D> {
        flatMapT { _decode($0, using: decoder) }
    }

    /// Decodes the raw `Data` output using the provided `DataDecoderFactory`.
    func decode<D: Decodable & Sendable>(
        using factory: DataDecoderFactory,
        type: D.Type = D.self
    ) -> NetworkTask<D> {
        decode(using: factory.dataDecoder(for: D.self))
    }
}
