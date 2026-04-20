import Foundation

public extension DecoderResult where D: Decodable {
    static var json: DecoderResult<D> { JSONDecoder().decoderResult(for: D.self) }
}
