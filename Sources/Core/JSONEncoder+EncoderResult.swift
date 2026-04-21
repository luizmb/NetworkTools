import Foundation
import FP

public protocol EncoderResultFactory {
    func encoderResult<E: Encodable>(for type: E.Type) -> EncoderResult<E>
}

extension JSONEncoder: EncoderResultFactory {
    public func encoderResult<E: Encodable>(for _: E.Type = E.self) -> EncoderResult<E> {
        EncoderResult { [self] value in
            Result { try encode(value) }
                .mapError {
                    $0 as? EncodingError
                        ?? EncodingError.invalidValue(
                            value,
                            .init(codingPath: [], debugDescription: "Unknown encoding error: \($0)")
                        )
                }
        }
    }
}

