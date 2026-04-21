import Core
import Foundation
import NIOHTTP1

// MARK: - Success factories

public extension Result where Success == Response, Failure == ResponseError {
    /// Encodes `entity` using `encoder` and returns a JSON response.
    static func from<E: Encodable>(
        encoder: EncoderResultFactory,
        entity: E,
        status: HTTPResponseStatus = .ok
    ) -> Self {
        encoder.encoderResult(for: E.self).run(entity)
            .map { Response(status: status, headers: [("Content-Type", "application/json")], body: $0) }
            .mapError { ResponseError(status: .internalServerError, body: Data($0.localizedDescription.utf8)) }
    }

    static func html(_ string: String, status: HTTPResponseStatus = .ok) -> Self {
        ResponseEncoder<String>.html.response(string, status: status)
    }

    static func plainText(_ string: String, status: HTTPResponseStatus = .ok) -> Self {
        ResponseEncoder<String>.plainText.response(string, status: status)
    }

    static func raw(_ data: Data, status: HTTPResponseStatus = .ok) -> Self {
        ResponseEncoder<Data>.raw.response(data, status: status)
    }
}

// MARK: - Failure factories

public extension Result where Success == Response, Failure == ResponseError {
    static var notFound: Self { .failure(.notFound) }
    static func badRequest(_ msg: String = "") -> Self { .failure(.badRequest(msg)) }
    static func serverError(_ msg: String = "") -> Self { .failure(.serverError(msg)) }
}
