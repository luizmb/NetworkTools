import FP
import Foundation

public protocol EncoderResultFactory {
    func encoderResult<E: Encodable>(for type: E.Type) -> EncoderResult<E>
}

extension JSONEncoder: EncoderResultFactory {
    public func encoderResult<E: Encodable>(for type: E.Type = E.self) -> EncoderResult<E> {
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

public extension EncoderResult where E: Encodable {
    static var json: Reader<JSONEncoder, EncoderResult<E>> {
        Reader { $0.encoderResult() }
    }
}
