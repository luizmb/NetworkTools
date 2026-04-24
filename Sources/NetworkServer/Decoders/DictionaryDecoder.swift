import Core
import Foundation

public typealias DictionaryDecoder<Output: Decodable> = Convert<[String: String], Output, DecodingError>

public protocol DictionaryDecoderFactory {
    func dictionaryDecoder<Output: Decodable>(for type: Output.Type) -> DictionaryDecoder<Output>
}

public protocol HasDictionaryDecoderFactory {
    var dictionaryDecoderFactory: DictionaryDecoderFactory { get }
}

extension StringKeyValueDecoder: DictionaryDecoderFactory {
    public func dictionaryDecoder<Output: Decodable>(for type: Output.Type = Output.self) -> DictionaryDecoder<Output> {
        Convert { data in
            Result { try Output(from: StringKeyValueDecoder(params: data)) }
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
