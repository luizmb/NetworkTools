import Core
import Foundation
import NIOHTTP1

// MARK: - Success factories

public extension Result where Success == Response, Failure == ResponseError {
    static func json<E: Encodable>(_ entity: E, encoder: EncoderResultFactory, status: HTTPResponseStatus = .ok) -> Self {
        encoder.encoderResult(for: E.self).run(entity)
            .map { Response(status: status, headers: [("Content-Type", "application/json")], body: $0) }
            .mapError { ResponseError(status: .internalServerError, body: Data($0.localizedDescription.utf8)) }
    }

    static func html(_ string: String, status: HTTPResponseStatus = .ok) -> Self {
        .success(Response(status: status, headers: [("Content-Type", "text/html; charset=utf-8")], body: Data(string.utf8)))
    }

    static func plainText(_ string: String, status: HTTPResponseStatus = .ok) -> Self {
        .success(Response(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")], body: Data(string.utf8)))
    }

    static func raw(_ data: Data, status: HTTPResponseStatus = .ok) -> Self {
        .success(Response(status: status, headers: [("Content-Type", "application/octet-stream")], body: data))
    }

    static func image(_ data: Data, mimeType: String = "image/jpeg", status: HTTPResponseStatus = .ok) -> Self {
        .success(Response(status: status, headers: [("Content-Type", mimeType)], body: data))
    }
}

// MARK: - Failure factories

public extension Result where Success == Response, Failure == ResponseError {
    static var notFound: Self { .failure(.notFound) }
    static func badRequest(_ msg: String = "") -> Self { .failure(.badRequest(msg)) }
    static func serverError(_ msg: String = "") -> Self { .failure(.serverError(msg)) }
}
