import Core
import Foundation
import FP
import NIOHTTP1

public struct ResponseEncoder<T>: @unchecked Sendable {
    public let contentType: String
    let encoder: EncoderResult<T>

    public init(contentType: String, _ encoder: EncoderResult<T>) {
        self.contentType = contentType
        self.encoder     = encoder
    }

    public func callAsFunction(_ value: T) -> Result<Data, EncodingError> { encoder.run(value) }

    public func response(_ value: T, status: HTTPResponseStatus = .ok) -> Result<Response, ResponseError> {
        encoder.run(value)
            .map { Response(status: status, headers: [("Content-Type", contentType)], body: $0) }
            .mapError { ResponseError(status: .internalServerError, headers: [], body: Data($0.localizedDescription.utf8)) }
    }
}

extension ResponseEncoder where T == Data {
    public static var raw: Self {
        Self(contentType: "application/octet-stream", EncoderResult { .success($0) })
    }

    public static func image(mimeType: String = "image/jpeg") -> Self {
        Self(contentType: mimeType, EncoderResult { .success($0) })
    }
}

extension ResponseEncoder where T == String {
    public static var html: Self {
        Self(contentType: "text/html; charset=utf-8", EncoderResult { .success(Data($0.utf8)) })
    }

    public static var plainText: Self {
        Self(contentType: "text/plain; charset=utf-8", EncoderResult { .success(Data($0.utf8)) })
    }
}

extension ResponseEncoder where T: Encodable {
    public static var json: Reader<EncoderResult<T>, Self> {
        Reader { Self(contentType: "application/json", $0) }
    }
}
