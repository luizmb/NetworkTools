import Foundation
import FP

public protocol DecoderResultFactory {
    func decoderResult<D: Decodable>(for type: D.Type) -> DecoderResult<D>
}

extension JSONDecoder: DecoderResultFactory {
    public func decoderResult<D: Decodable>(for type: D.Type) -> DecoderResult<D> {
        DecoderResult { [self] data in
            Result { try decode(type, from: data) }
                .mapError {
                    $0 as? DecodingError
                        ?? DecodingError.dataCorrupted(.init(
                            codingPath: [],
                            debugDescription: "Unknown decoding error: \($0)"
                        ))
                }
        }
    }
}
