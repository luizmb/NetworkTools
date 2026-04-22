import Foundation
import FP

public typealias DataEncoder<Input: Encodable> = Convert<Input, Data, EncodingError>

public protocol DataEncoderFactory {
    func dataEncoder<Input: Encodable>(for type: Input.Type) -> DataEncoder<Input>
}

public protocol HasDataEncoderFactory {
    var dataEncoderFactory: DataEncoderFactory { get }
}

extension JSONEncoder: DataEncoderFactory {
    public func dataEncoder<Input: Encodable>(for _: Input.Type = Input.self) -> DataEncoder<Input> {
        Convert { [self] value in
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

