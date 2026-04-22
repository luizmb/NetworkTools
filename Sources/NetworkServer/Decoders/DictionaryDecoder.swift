import Foundation
import Core

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

/// The default router environment for routers that need no custom state.
/// Provides `StringKeyValueDecoder` as the `DictionaryDecoderFactory` for route
/// parameter and query-string decoding.
///
/// Use this when building `Router<DefaultEnv>` with `when(_:)`:
/// ```swift
/// let router = when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
/// startServer(port: 8080, router: router).runReader(DefaultEnv())
/// ```
public struct DefaultEnv: HasDictionaryDecoderFactory, Sendable {
    public var dictionaryDecoderFactory: DictionaryDecoderFactory { StringKeyValueDecoder(params: [:]) }
    public init() {}
}

