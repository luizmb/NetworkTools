// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
@testable import NetworkClient
import ReactiveConcurrency
import ReactiveConcurrencyOperators
import ReactiveConcurrencyTransformers
import Testing

// `NetworkTask<A>` is now `Reader<URLRequest, Publisher<A, HTTPError>>` (a `ReaderTPublisher`).
// The generic Functor/Monad laws live in ReactiveConcurrency's own transformer suite; these tests
// cover NetworkTask's own behavior: value/error transformation and the HTTP-specific steps
// (`validateStatusCode`, `decode`).

private extension Result {
    var successValue: Success? { if case let .success(v) = self { v } else { nil } }
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

// swiftlint:disable:next force_unwrapping
private let mockRequest = URLRequest(url: URL(string: "https://example.com")!)

// MARK: - Helpers

private func just<A: Sendable>(_ value: A) -> NetworkTask<A> {
    Reader { _ in Publisher.pure(value) }
}

private func fail<A: Sendable>(_ error: HTTPError) -> NetworkTask<A> {
    Reader { _ in Publisher.fail(error) }
}

/// Runs the task against the mock request and awaits its single result.
private func run<A: Sendable>(_ t: NetworkTask<A>) async -> Result<A, HTTPError> {
    await t(mockRequest).firstResultTask().run() ?? .failure(.badStatus(-1, Data()))
}

// MARK: - NetworkTask: transformation

@Suite("NetworkTask — transformation")
struct NetworkTaskTransformTests {
    @Test func mapT_transformsSuccess() async {
        #expect(await run(just(3).mapT { $0 * 7 }).successValue == 21)
    }

    @Test func mapT_passesFailure() async {
        #expect(await run(fail(.badStatus(404, Data())).mapT { (_: Int) in 0 }).isFailure == true)
    }

    @Test func flatMapT_chains() async {
        #expect(await run(just(5).flatMapT { n in just("\(n)!") }).successValue == "5!")
    }

    @Test func flatMapT_propagatesFailure() async {
        #expect(await run(fail(.badStatus(500, Data())).flatMapT { (_: Int) in just("x") }).isFailure == true)
    }

    @Test func kleisliOp_composes() async {
        let f: @Sendable (Int) -> NetworkTask<Int> = { n in just(n + 1) }
        let g: @Sendable (Int) -> NetworkTask<String> = { n in just("\(n)") }
        #expect(await run((f >=> g)(41)).successValue == "42")
    }

    @Test func mapError_transformsFailure() async {
        let t: NetworkTask<Int> = fail(.badStatus(404, Data())).map { $0.mapError { _ in .badStatus(999, Data()) } }
        guard case let .failure(.badStatus(code, _)) = await run(t) else {
            Issue.record("Expected .failure(.badStatus(999, _))")
            return
        }
        #expect(code == 999)
    }

    @Test func catch_recovers() async {
        let recovered: NetworkTask<Int> = fail(.badStatus(500, Data())).map { $0.catch { _ in Publisher.pure(0) } }
        #expect(await run(recovered).successValue == 0)
    }

    @Test func catch_passesSuccessThrough() async {
        let recovered: NetworkTask<Int> = just(42).map { $0.catch { _ in Publisher.pure(0) } }
        #expect(await run(recovered).successValue == 42)
    }
}

// MARK: - NetworkTask: Status code

@Suite("NetworkTask — validateStatusCode")
struct NetworkTaskValidateStatusCodeTests {
    private func makeTask(status: Int, body: Data = Data()) -> NetworkTask<(Data, HTTPURLResponse)> {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://x.com")!
        // swiftlint:disable:next force_unwrapping
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return Reader { _ in Publisher.pure((body, resp)) }
    }

    @Test func status200_succeeds() async {
        let body = Data("ok".utf8)
        #expect(await run(makeTask(status: 200, body: body).validateStatusCode()).successValue == body)
    }

    @Test func status201_succeeds() async { #expect(await run(makeTask(status: 201).validateStatusCode()).isFailure != true) }
    @Test func status299_succeeds() async { #expect(await run(makeTask(status: 299).validateStatusCode()).isFailure != true) }

    @Test func status300_fails() async { #expect(await run(makeTask(status: 300).validateStatusCode()).isFailure == true) }
    @Test func status400_fails() async {
        guard case let .failure(.badStatus(code, _)) = await run(makeTask(status: 400).validateStatusCode()) else {
            Issue.record("Expected .badStatus(400, _)")
            return
        }
        #expect(code == 400)
    }

    @Test func status404_fails() async { #expect(await run(makeTask(status: 404).validateStatusCode()).isFailure == true) }
    @Test func status500_fails() async { #expect(await run(makeTask(status: 500).validateStatusCode()).isFailure == true) }

    @Test func badStatusCarriesBody() async {
        let errorBody = Data("detail".utf8)
        guard case let .failure(.badStatus(_, body)) = await run(makeTask(status: 422, body: errorBody).validateStatusCode()) else {
            Issue.record("Expected .badStatus with body")
            return
        }
        #expect(body == errorBody)
    }
}

// MARK: - NetworkTask: Decoding

private struct Person: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

private let personJSON = Data(#"{"id":1,"name":"Alice"}"#.utf8)
private let invalidJSON = Data("not json".utf8)

@Suite("NetworkTask — decode")
struct NetworkTaskDecodeTests {
    private let decoder = JSONDecoder().dataDecoder(for: Person.self)

    @Test func decodesValidJSON() async {
        #expect(await run(just(personJSON).decode(using: decoder)).successValue == Person(id: 1, name: "Alice"))
    }

    @Test func failsOnInvalidJSON() async {
        #expect(await run(just(invalidJSON).decode(using: decoder)).isFailure == true)
    }

    @Test func upstreamFailurePassesThrough() async {
        #expect(await run(fail(.badStatus(500, Data())).decode(using: decoder)).isFailure == true)
    }

    @Test func decodingErrorIsWrappedInHTTPError() async {
        guard case .failure(.decoding) = await run(just(invalidJSON).decode(using: decoder)) else {
            Issue.record("Expected .failure(.decoding)")
            return
        }
    }

    @Test func mapAfterDecode() async {
        #expect(await run(just(personJSON).decode(using: decoder).mapT(\.name)).successValue == "Alice")
    }
}
