// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
import ReactiveConcurrency

public extension Publisher where Output == Data, Failure == HTTPError {
    /// Decodes the raw `Data` output using the provided `DataDecoder`.
    func decode<D: Decodable & Sendable>(using decoder: DataDecoder<D>) -> Publisher<D, HTTPError> {
        flatMap { data -> Publisher<D, HTTPError> in
            Publisher<D, HTTPError>.future { decoder.run(data).mapError(HTTPError.decoding) }
        }
    }

    /// Decodes the raw `Data` output using any `DataDecoderFactory` (JSON, Plist, XML, YAML…).
    func decode<D: Decodable & Sendable>(using factory: DataDecoderFactory, type: D.Type = D.self) -> Publisher<D, HTTPError> {
        decode(using: factory.dataDecoder(for: D.self))
    }
}
