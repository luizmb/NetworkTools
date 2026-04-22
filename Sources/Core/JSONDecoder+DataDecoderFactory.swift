import Foundation
import FP

public typealias DataDecoder<Output: Decodable> = Convert<Data, Output, DecodingError>

public protocol DataDecoderFactory {
    func dataDecoder<Output: Decodable>(for type: Output.Type) -> DataDecoder<Output>
}

public protocol HasDataDecoderFactory {
    var dataDecoderFactory: DataDecoderFactory { get }
}

extension JSONDecoder: DataDecoderFactory {
    public func dataDecoder<Output: Decodable>(for type: Output.Type = Output.self) -> DataDecoder<Output> {
        Convert { [self] data in
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
