import FP
import Foundation

public extension DecoderResult where D: Decodable {
    static var json: Reader<JSONDecoder, DecoderResult<D>> {
        Reader { $0.decoderResult(for: D.self) }
    }
}
