import Core
import Foundation
import FP
@testable import NetworkClient
import Testing

private extension Result {
    var successValue: Success? { if case .success(let v) = self { v } else { nil } }
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

// swiftlint:disable:next force_unwrapping
private let mockRequest = URLRequest(url: URL(string: "https://example.com")!)

// MARK: - Helpers

private func just<A: Sendable>(_ value: A) -> NetworkTask<A> {
    .pure(value)
}

private func fail<A: Sendable>(_ error: HTTPError) -> NetworkTask<A> {
    ZIO { _ in DeferredTask { .failure(error) } }
}

private func run<A: Sendable>(_ t: NetworkTask<A>) async -> Result<A, HTTPError> {
    await t(mockRequest).run()
}

// MARK: - NetworkTask: Functor

@Suite("NetworkTask — Functor")
struct NetworkTaskFunctorTests {
    @Test func pure() async { #expect(await run(NetworkTask<Int>.pure(42)).successValue == 42) }
    @Test func map_transformsSuccess() async { #expect(await run(just(3).map { $0 * 7 }).successValue == 21) }
    @Test func map_passesFailure() async { #expect(await run(fail(.badStatus(404, Data())).map { (_: Int) in 0 }).isFailure == true) }
    @Test func replace() async { #expect(await run(just(99).replace("x")).successValue == "x") }

    @Test func fmap_curried() async {
        let lift = ZIO<URLRequest, Int, HTTPError>.fmap { $0 + 1 }
        #expect(await run(lift(just(41))).successValue == 42)
    }

    @Test func mapError_transformsFailure() async {
        let t: NetworkTask<Int> = (fail(.badStatus(404, Data())) as NetworkTask<Int>).mapError { _ in .badStatus(999, Data()) }
        guard case .failure(let e) = await run(t), case .badStatus(let code, _) = e else {
            Issue.record("Expected .failure(.badStatus(999, _))")
            return
        }
        #expect(code == 999)
    }
}

// MARK: - NetworkTask: Applicative

@Suite("NetworkTask — Applicative")
struct NetworkTaskApplicativeTests {
    @Test func apply_combinesFunctionAndValue() async {
        let f = NetworkTask<@Sendable (Int) -> String>.pure(String.init)
        #expect(await run(f <*> just(42)).successValue == "42")
    }

    @Test func apply_propagatesLeftFailure() async {
        let f = fail(.badStatus(500, Data())) as NetworkTask<@Sendable (Int) -> Int>
        #expect(await run(f <*> just(1)).isFailure == true)
    }

    @Test func apply_propagatesRightFailure() async {
        let f = just { @Sendable (n: Int) in n + 1 }
        let a = fail(.badStatus(500, Data())) as NetworkTask<Int>
        #expect(await run(f <*> a).isFailure == true)
    }

    @Test func seqRight_discardsLeft() async { #expect(await run(just(1).seqRight(just("kept"))).successValue == "kept") }
    @Test func seqLeft_discardsRight() async { #expect(await run(just(99).seqLeft(just("x"))).successValue == 99) }
}

// MARK: - NetworkTask: Monad

@Suite("NetworkTask — Monad")
struct NetworkTaskMonadTests {
    @Test func flatMap_chains() async {
        #expect(await run(just(5).flatMap { n in just("\(n)!") }).successValue == "5!")
    }

    @Test func flatMap_propagatesFailure() async {
        #expect(await run(fail(.badStatus(500, Data())).flatMap { (_: Int) in just("x") }).isFailure == true)
    }

    @Test func bind_curried() async {
        let f = ZIO<URLRequest, Int, HTTPError>.bind { n in just(n * 2) }
        #expect(await run(f(just(6))).successValue == 12)
    }

    @Test func join_flattens() async {
        let nested: NetworkTask<NetworkTask<Int>> = just(just(7))
        #expect(await run(ZIO<URLRequest, NetworkTask<Int>, HTTPError>.join(nested)).successValue == 7)
    }

    @Test func kleisli_composes() async {
        let f: @Sendable (String) -> NetworkTask<Int> = { s in just(s.count) }
        let g: @Sendable (Int) -> NetworkTask<String> = { n in just("\(n)") }
        #expect(await run(ZIO<URLRequest, Int, HTTPError>.kleisli(f, g)("hello")).successValue == "5")
    }

    @Test func kleisliBack_composes() async {
        let f: @Sendable (String) -> NetworkTask<Int> = { s in just(s.count) }
        let g: @Sendable (Int) -> NetworkTask<String> = { n in just("\(n)") }
        #expect(await run(ZIO<URLRequest, Int, HTTPError>.kleisliBack(g, f)("hello")).successValue == "5")
    }

    @Test func flatMapError_recovers() async {
        #expect(await run(fail(.badStatus(500, Data())).flatMapError { _ in just(0) }).successValue == 0)
    }

    @Test func flatMapError_passesSuccessThrough() async {
        #expect(await run(just(42).flatMapError { _ in just(0) }).successValue == 42)
    }
}

// MARK: - NetworkTask: Operators

@Suite("NetworkTask — Operators")
struct NetworkTaskOperatorTests {
    @Test func fmapOp() async { #expect(await run({ $0 * 2 } <£> just(5)).successValue == 10) }
    @Test func flippedFmapOp() async { #expect(await run(just(5) <&> { $0 * 2 }).successValue == 10) }
    @Test func replaceRightOp() async { #expect(await run(just(5) £> "r").successValue == "r") }
    @Test func replaceLeftOp() async { #expect(await run("r" <£ just(5)).successValue == "r") }

    @Test func applyOp() async {
        let f = just { @Sendable (n: Int) in n + 1 }
        #expect(await run(f <*> just(41)).successValue == 42)
    }
    @Test func seqRightOp() async { #expect(await run(just(1) *> just("k")).successValue == "k") }
    @Test func seqLeftOp() async { #expect(await run(just(9) <* just("d")).successValue == 9) }

    @Test func bindOp() async { #expect(await run(just(3) >>- { n in just(n * n) }).successValue == 9) }
    @Test func flippedBindOp() async { #expect(await run({ n in just(n * n) } -<< just(3)).successValue == 9) }

    @Test func kleisliOp() async {
        let f: @Sendable (Int) -> NetworkTask<Int> = { n in just(n + 1) }
        let g: @Sendable (Int) -> NetworkTask<String> = { n in just("\(n)") }
        #expect(await run((f >=> g)(41)).successValue == "42")
    }
    @Test func kleisliBackOp() async {
        let f: @Sendable (Int) -> NetworkTask<Int> = { n in just(n + 1) }
        let g: @Sendable (Int) -> NetworkTask<String> = { n in just("\(n)") }
        #expect(await run((g <=< f)(41)).successValue == "42")
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
        return ZIO { _ in DeferredTask { .success((body, resp)) } }
    }

    @Test func status200_succeeds() async {
        let body = Data("ok".utf8)
        #expect(await run(makeTask(status: 200, body: body).validateStatusCode()).successValue == body)
    }

    @Test func status201_succeeds() async { #expect(await run(makeTask(status: 201).validateStatusCode()).isFailure != true) }
    @Test func status299_succeeds() async { #expect(await run(makeTask(status: 299).validateStatusCode()).isFailure != true) }

    @Test func status300_fails() async { #expect(await run(makeTask(status: 300).validateStatusCode()).isFailure == true) }
    @Test func status400_fails() async {
        guard case .failure(let e) = await run(makeTask(status: 400).validateStatusCode()),
              case .badStatus(let code, _) = e else {
            Issue.record("Expected .badStatus(400, _)")
            return
        }
        #expect(code == 400)
    }
    @Test func status404_fails() async { #expect(await run(makeTask(status: 404).validateStatusCode()).isFailure == true) }
    @Test func status500_fails() async { #expect(await run(makeTask(status: 500).validateStatusCode()).isFailure == true) }

    @Test func badStatusCarriesBody() async {
        let errorBody = Data("detail".utf8)
        guard case .failure(let e) = await run(makeTask(status: 422, body: errorBody).validateStatusCode()),
              case .badStatus(_, let body) = e else {
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

private let personJSON  = Data(#"{"id":1,"name":"Alice"}"#.utf8)
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
        guard case .failure(let e) = await run(just(invalidJSON).decode(using: decoder)),
              case .decoding = e else {
            Issue.record("Expected .failure(.decoding)")
            return
        }
    }

    @Test func mapAfterDecode() async {
        #expect(await run(just(personJSON).decode(using: decoder).map(\.name)).successValue == "Alice")
    }
}
