import Core
import Foundation
import NIOHTTP1

public struct ResponseError: Error, @unchecked Sendable {
    public let status: HTTPResponseStatus
    public let headers: [(String, String)]
    public let body: Data

    public init(status: HTTPResponseStatus, headers: [(String, String)] = [], body: Data = Data()) {
        self.status  = status
        self.headers = headers
        self.body    = body
    }
}

// MARK: - Common errors

public extension ResponseError {
    static var notFound: ResponseError {
        ResponseError(status: .notFound, headers: [("Content-Type", "text/plain")], body: Data("Not Found".utf8))
    }

    static func badRequest(_ msg: String = "") -> ResponseError {
        ResponseError(status: .badRequest, headers: [("Content-Type", "text/plain")], body: Data(msg.utf8))
    }

    static func serverError(_ msg: String = "") -> ResponseError {
        ResponseError(status: .internalServerError, headers: [("Content-Type", "text/plain")], body: Data(msg.utf8))
    }
}

// MARK: - Encoded errors

public extension ResponseError {
    static func json<T: Encodable>(
        _ value: T,
        encoder: DataEncoderFactory,
        status: HTTPResponseStatus = .internalServerError
    ) -> ResponseError {
        switch encoder.dataEncoder(for: T.self).run(value) {
        case .success(let data):
            ResponseError(status: status, headers: [("Content-Type", "application/json")], body: data)
        case .failure(let e):
            ResponseError(status: .internalServerError, body: Data(e.localizedDescription.utf8))
        }
    }

    static func html(_ string: String, status: HTTPResponseStatus = .internalServerError) -> ResponseError {
        ResponseError(status: status, headers: [("Content-Type", "text/html; charset=utf-8")], body: Data(string.utf8))
    }
}
