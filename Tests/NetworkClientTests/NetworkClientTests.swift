// swiftlint:disable file_length
import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
@testable import NetworkClient
import Testing
#if canImport(Combine)
import Combine
#endif

// MARK: - Test fixtures

private struct Person: Codable, Equatable {
    let id: Int
    let name: String
}

private let personJSON  = Data(#"{"id":1,"name":"Alice"}"#.utf8)
private let invalidJSON = Data("not json".utf8)

private extension Result {
    var successValue: Success? { if case .success(let v) = self { v } else { nil } }
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

#if canImport(Combine)
// swiftlint:disable:next force_unwrapping
private let mockRequest = URLRequest(url: URL(string: "https://example.com")!)

// MARK: - Helpers

private func firstResult<O, E: Error>(of publisher: AnyPublisher<O, E>) -> Result<O, E>? {
    var result: Result<O, E>?
    let token = publisher.first().sink(
        receiveCompletion: { if case .failure(let e) = $0 { result = .failure(e) } },
        receiveValue: { result = .success($0) }
    )
    withExtendedLifetime(token) {}
    return result
}

// MARK: - RequestPublisher builders

private func just<A>(_ value: A) -> RequestPublisher<A> {
    RequestPublisher { _ in Just(value).setFailureType(to: HTTPError.self).eraseToAnyPublisher() }
}

private func fail<A>(_ error: HTTPError) -> RequestPublisher<A> {
    RequestPublisher { _ in Fail(error: error).eraseToAnyPublisher() }
}

private func run<A>(_ p: RequestPublisher<A>) -> Result<A, HTTPError>? {
    firstResult(of: p(mockRequest))
}
#endif

// MARK: - DataDecoder: Functor

@Suite("DataDecoder — Functor")
struct DataDecoderFunctorTests {
    @Test func pure() {
        #expect(DataDecoder<Int>.pure(42).run(Data()).successValue == 42)
    }

    @Test func map_transformsSuccess() {
        #expect(DataDecoder<Int>.pure(3).map { $0 * 7 }.run(Data()).successValue == 21)
    }

    @Test func map_passesFailureThrough() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        #expect(DataDecoder<Int> { _ in .failure(err) }.map { $0 + 1 }.run(Data()).isFailure)
    }

    @Test func fmap_curried() {
        let lift = DataDecoder<Int>.fmap { $0 * 2 }
        #expect(lift(DataDecoder.pure(5)).run(Data()).successValue == 10)
    }

    @Test func replace() {
        #expect(DataDecoder<Int>.pure(99).replace(with: "x").run(Data()).successValue == "x")
    }

    @Test func mapError_transformsFailure() {
        let original = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "orig"))
        let replaced = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "new"))
        let result = DataDecoder<Int> { _ in .failure(original) }
            .mapError { _ in replaced }
            .run(Data())
        guard case .failure(let e) = result, case .dataCorrupted(let ctx) = e else {
            Issue.record("Expected .failure(.dataCorrupted)")
            return
        }
        #expect(ctx.debugDescription == "new")
    }
}

// Convert<Data, _, DecodingError> is used below instead of DataDecoder<_> because
// DataDecoder constrains Output: Decodable, but these tests use function types as Output.
private typealias AnyDataConvert<T> = Convert<Data, T, DecodingError>

// MARK: - DataDecoder: Applicative

@Suite("DataDecoder — Applicative")
struct DataDecoderApplicativeTests {
    @Test func apply_combinesFunctionAndValue() {
        let f = AnyDataConvert<(Int) -> String>.pure(String.init)
        let a = AnyDataConvert<Int>.pure(42)
        #expect(AnyDataConvert.apply(f, a).run(Data()).successValue == "42")
    }

    @Test func apply_propagatesLeftFailure() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        let f   = AnyDataConvert<(Int) -> Int> { _ in .failure(err) }
        #expect(AnyDataConvert.apply(f, .pure(1)).run(Data()).isFailure)
    }

    @Test func apply_propagatesRightFailure() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        let f   = AnyDataConvert<(Int) -> Int>.pure { $0 + 1 }
        let a   = AnyDataConvert<Int> { _ in .failure(err) }
        #expect(AnyDataConvert.apply(f, a).run(Data()).isFailure)
    }

    @Test func seqRight_discardsLeft() {
        #expect(AnyDataConvert<Int>.pure(1).seqRight(AnyDataConvert.pure("kept")).run(Data()).successValue == "kept")
    }

    @Test func seqLeft_discardsRight() {
        #expect(AnyDataConvert<Int>.pure(99).seqLeft(AnyDataConvert<String>.pure("x")).run(Data()).successValue == 99)
    }
}

// MARK: - DataDecoder: Monad

@Suite("DataDecoder — Monad")
struct DataDecoderMonadTests {
    @Test func flatMap_chains() {
        let dr = AnyDataConvert<Int>.pure(5).flatMap { n in AnyDataConvert.pure("\(n)!") }
        #expect(dr.run(Data()).successValue == "5!")
    }

    @Test func flatMap_propagatesUpstreamFailure() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        let dr  = AnyDataConvert<Int> { _ in .failure(err) }.flatMap { n in AnyDataConvert.pure("\(n)") }
        #expect(dr.run(Data()).isFailure)
    }

    @Test func bind_curried() {
        let f = AnyDataConvert<Int>.bind { n in AnyDataConvert.pure(n * 2) }
        #expect(f(AnyDataConvert.pure(6)).run(Data()).successValue == 12)
    }

    @Test func kleisli_composes() {
        let f: (String) -> AnyDataConvert<Int> = { s in .pure(s.count) }
        let g: (Int) -> AnyDataConvert<String> = { n in .pure("\(n)") }
        #expect(AnyDataConvert.kleisli(f, g)("hello").run(Data()).successValue == "5")
    }

    @Test func kleisliBack_composes() {
        let f: (String) -> AnyDataConvert<Int> = { s in .pure(s.count) }
        let g: (Int) -> AnyDataConvert<String> = { n in .pure("\(n)") }
        #expect(AnyDataConvert.kleisliBack(g, f)("hello").run(Data()).successValue == "5")
    }

    @Test func flatMapError_recovers() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        let dr: AnyDataConvert<Int> = AnyDataConvert { _ in .failure(err) }.flatMapError { _ in .pure(0) }
        #expect(dr.run(Data()).successValue == 0)
    }

    @Test func flatMapError_passesSuccessThrough() {
        let dr: AnyDataConvert<Int> = AnyDataConvert.pure(42).flatMapError { _ in .pure(0) }
        #expect(dr.run(Data()).successValue == 42)
    }
}

// MARK: - DataDecoder: Operators

@Suite("DataDecoder — Operators")
struct DataDecoderOperatorTests {
    @Test func fmapOp() { #expect(({ $0 * 2 } <£> AnyDataConvert<Int>.pure(5)).run(Data()).successValue == 10) }
    @Test func flippedFmapOp() { #expect((AnyDataConvert<Int>.pure(5) <&> { $0 * 2 }).run(Data()).successValue == 10) }
    @Test func replaceRightOp() { #expect((AnyDataConvert<Int>.pure(5) £> "r").run(Data()).successValue == "r") }
    @Test func replaceLeftOp() { #expect(("r" <£ AnyDataConvert<Int>.pure(5)).run(Data()).successValue == "r") }

    @Test func applyOp() {
        let f = AnyDataConvert<(Int) -> Int>.pure { $0 + 1 }
        #expect((f <*> AnyDataConvert<Int>.pure(41)).run(Data()).successValue == 42)
    }
    @Test func seqRightOp() { #expect((AnyDataConvert<Int>.pure(1) *> AnyDataConvert<String>.pure("k")).run(Data()).successValue == "k") }
    @Test func seqLeftOp() { #expect((AnyDataConvert<Int>.pure(9) <* AnyDataConvert<String>.pure("d")).run(Data()).successValue == 9) }

    @Test func bindOp() { #expect((AnyDataConvert<Int>.pure(3) >>- { n in .pure(n * n) }).run(Data()).successValue == 9) }
    @Test func flippedBindOp() {
        #expect(({ n in AnyDataConvert<Int>.pure(n * n) } -<< AnyDataConvert<Int>.pure(3)).run(Data()).successValue == 9)
    }

    @Test func kleisliOp() {
        let f: (Int) -> AnyDataConvert<Int> = { n in .pure(n + 1) }
        let g: (Int) -> AnyDataConvert<String> = { n in .pure("\(n)") }
        #expect((f >=> g)(41).run(Data()).successValue == "42")
    }
    @Test func kleisliBackOp() {
        let f: (Int) -> AnyDataConvert<Int> = { n in .pure(n + 1) }
        let g: (Int) -> AnyDataConvert<String> = { n in .pure("\(n)") }
        #expect((g <=< f)(41).run(Data()).successValue == "42")
    }
}

// MARK: - Convert: generic input/output

@Suite("Convert — generic")
struct ConvertGenericTests {
    @Test func intToString() {
        let c = Convert<Int, String, Never> { .success(String($0)) }
        #expect(c.run(42).successValue == "42")
    }

    @Test func contramap_preProcessesInput() {
        let countDigits = Convert<Int, Int, Never> { .success(String($0).count) }
        let fromString  = countDigits.contramap { (s: String) in s.count }
        #expect(fromString.run("hello").successValue == 1) // count("hello") = 5, digits in 5 = 1
    }

    @Test func map_chainedTransformation() {
        let base: Convert<Int, Int, Never> = .pure(7)
        #expect(base.map { $0 * $0 }.map(String.init).run(0).successValue == "49")
    }
}

// MARK: - JSONDecoder + DataDecoderFactory

@Suite("JSONDecoder — DataDecoderFactory")
struct JSONDecoderDataDecoderTests {
    @Test func decodesValidJSON() {
        #expect(JSONDecoder().dataDecoder(for: Person.self).run(personJSON).successValue == Person(id: 1, name: "Alice"))
    }

    @Test func failsOnInvalidJSON() {
        #expect(JSONDecoder().dataDecoder(for: Person.self).run(invalidJSON).isFailure)
    }

    @Test func failsOnMissingField() {
        let json = Data(#"{"id":1}"#.utf8)
        #expect(JSONDecoder().dataDecoder(for: Person.self).run(json).isFailure)
    }

    @Test func mapTransformsDecodedValue() {
        let name = JSONDecoder().dataDecoder(for: Person.self).map(\.name).run(personJSON).successValue
        #expect(name == "Alice")
    }
}

#if canImport(Combine)
// MARK: - RequestPublisher: Functor

@Suite("RequestPublisher — Functor")
struct RequestPublisherFunctorTests {
    @Test func pure() { #expect(run(RequestPublisher<Int>.pure(42))?.successValue == 42) }
    @Test func map_transformsSuccess() { #expect(run(just(3).map { $0 * 7 })?.successValue == 21) }
    @Test func map_passesFailure() { #expect(run(fail(.badStatus(404, Data())).map { (_: Int) in 0 })?.isFailure == true) }
    @Test func replace() { #expect(run(just(99).replace(with: "x"))?.successValue == "x") }

    @Test func fmap_curried() {
        let lift = RequestPublisher<Int>.fmap { $0 + 1 }
        #expect(run(lift(just(41)))?.successValue == 42)
    }

    @Test func mapError_transformsFailure() {
        let p = (fail(.badStatus(404, Data())) as RequestPublisher<Int>).mapError { _ in .badStatus(999, Data()) }
        guard case .failure(let e) = run(p), case .badStatus(let code, _) = e else {
            Issue.record("Expected .failure(.badStatus(999, _))")
            return
        }
        #expect(code == 999)
    }
}

// MARK: - RequestPublisher: Applicative

@Suite("RequestPublisher — Applicative")
struct RequestPublisherApplicativeTests {
    @Test func apply_combinesFunctionAndValue() {
        let f = RequestPublisher<(Int) -> String>.pure(String.init)
        #expect(run(RequestPublisher.apply(f, just(42)))?.successValue == "42")
    }

    @Test func apply_propagatesLeftFailure() {
        let f = fail(.badStatus(500, Data())) as RequestPublisher<(Int) -> Int>
        #expect(run(RequestPublisher.apply(f, just(1)))?.isFailure == true)
    }

    @Test func apply_propagatesRightFailure() {
        let f = just { (n: Int) in n + 1 }
        let a = fail(.badStatus(500, Data())) as RequestPublisher<Int>
        #expect(run(RequestPublisher.apply(f, a))?.isFailure == true)
    }

    @Test func seqRight_discardsLeft() { #expect(run(just(1).seqRight(just("kept")))?.successValue == "kept") }
    @Test func seqLeft_discardsRight() { #expect(run(just(99).seqLeft(just("x")))?.successValue == 99) }
}

// MARK: - RequestPublisher: Monad

@Suite("RequestPublisher — Monad")
struct RequestPublisherMonadTests {
    @Test func flatMap_chains() {
        #expect(run(just(5).flatMap { n in just("\(n)!") })?.successValue == "5!")
    }

    @Test func flatMap_propagatesFailure() {
        #expect(run(fail(.badStatus(500, Data())).flatMap { (_: Int) in just("x") })?.isFailure == true)
    }

    @Test func bind_curried() {
        let f = RequestPublisher<Int>.bind { n in just(n * 2) }
        #expect(run(f(just(6)))?.successValue == 12)
    }

    @Test func join_flattens() {
        let nested = just(just(7)) as RequestPublisher<RequestPublisher<Int>>
        #expect(run(RequestPublisher.join(nested))?.successValue == 7)
    }

    @Test func kleisli_composes() {
        let f: (String) -> RequestPublisher<Int> = { s in just(s.count) }
        let g: (Int) -> RequestPublisher<String> = { n in just("\(n)") }
        #expect(run(RequestPublisher.kleisli(f, g)("hello"))?.successValue == "5")
    }

    @Test func kleisliBack_composes() {
        let f: (String) -> RequestPublisher<Int> = { s in just(s.count) }
        let g: (Int) -> RequestPublisher<String> = { n in just("\(n)") }
        #expect(run(RequestPublisher.kleisliBack(g, f)("hello"))?.successValue == "5")
    }

    @Test func flatMapError_recovers() {
        #expect(run(fail(.badStatus(500, Data())).flatMapError { _ in just(0) })?.successValue == 0)
    }

    @Test func flatMapError_passesSuccessThrough() {
        #expect(run(just(42).flatMapError { _ in just(0) })?.successValue == 42)
    }
}

// MARK: - RequestPublisher: Operators

@Suite("RequestPublisher — Operators")
struct RequestPublisherOperatorTests {
    @Test func fmapOp() { #expect(run({ $0 * 2 } <£> just(5))?.successValue == 10) }
    @Test func flippedFmapOp() { #expect(run(just(5) <&> { $0 * 2 })?.successValue == 10) }
    @Test func replaceRightOp() { #expect(run(just(5) £> "r")?.successValue == "r") }
    @Test func replaceLeftOp() { #expect(run("r" <£ just(5))?.successValue == "r") }

    @Test func applyOp() {
        let f = just { (n: Int) in n + 1 }
        #expect(run(f <*> just(41))?.successValue == 42)
    }
    @Test func seqRightOp() { #expect(run(just(1) *> just("k"))?.successValue == "k") }
    @Test func seqLeftOp() { #expect(run(just(9) <* just("d"))?.successValue == 9) }

    @Test func bindOp() { #expect(run(just(3) >>- { n in just(n * n) })?.successValue == 9) }
    @Test func flippedBindOp() { #expect(run({ n in just(n * n) } -<< just(3))?.successValue == 9) }

    @Test func kleisliOp() {
        let f: (Int) -> RequestPublisher<Int> = { n in just(n + 1) }
        let g: (Int) -> RequestPublisher<String> = { n in just("\(n)") }
        #expect(run((f >=> g)(41))?.successValue == "42")
    }
    @Test func kleisliBackOp() {
        let f: (Int) -> RequestPublisher<Int> = { n in just(n + 1) }
        let g: (Int) -> RequestPublisher<String> = { n in just("\(n)") }
        #expect(run((g <=< f)(41))?.successValue == "42")
    }
}

// MARK: - RequestPublisher: Status code

@Suite("RequestPublisher — validateStatusCode")
struct ValidateStatusCodeTests {
    private func makePublisher(status: Int, body: Data = Data()) -> RequestPublisher<(Data, HTTPURLResponse)> {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://x.com")!
        // swiftlint:disable:next force_unwrapping
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return RequestPublisher { _ in
            Just((body, resp)).setFailureType(to: HTTPError.self).eraseToAnyPublisher()
        }
    }

    @Test func status200_succeeds() {
        let body = Data("ok".utf8)
        #expect(run(makePublisher(status: 200, body: body).validateStatusCode())?.successValue == body)
    }

    @Test func status201_succeeds() { #expect(run(makePublisher(status: 201).validateStatusCode())?.isFailure != true) }
    @Test func status299_succeeds() { #expect(run(makePublisher(status: 299).validateStatusCode())?.isFailure != true) }

    @Test func status300_fails() { #expect(run(makePublisher(status: 300).validateStatusCode())?.isFailure == true) }
    @Test func status400_fails() {
        guard case .failure(let e) = run(makePublisher(status: 400).validateStatusCode()),
              case .badStatus(let code, _) = e else {
            Issue.record("Expected .badStatus(400, _)")
            return
        }
        #expect(code == 400)
    }
    @Test func status404_fails() { #expect(run(makePublisher(status: 404).validateStatusCode())?.isFailure == true) }
    @Test func status500_fails() { #expect(run(makePublisher(status: 500).validateStatusCode())?.isFailure == true) }

    @Test func badStatusCarriesBody() {
        let errorBody = Data("detail".utf8)
        guard case .failure(let e) = run(makePublisher(status: 422, body: errorBody).validateStatusCode()),
              case .badStatus(_, let body) = e else {
            Issue.record("Expected .badStatus with body")
            return
        }
        #expect(body == errorBody)
    }
}

// MARK: - RequestPublisher: Decoding

@Suite("RequestPublisher — decode")
struct RequestPublisherDecodeTests {
    private let decoder = JSONDecoder().dataDecoder(for: Person.self)

    @Test func decodesValidJSON() {
        let p = just(personJSON).decode(using: decoder)
        #expect(run(p)?.successValue == Person(id: 1, name: "Alice"))
    }

    @Test func failsOnInvalidJSON() {
        #expect(run(just(invalidJSON).decode(using: decoder))?.isFailure == true)
    }

    @Test func upstreamFailurePassesThrough() {
        #expect(run(fail(.badStatus(500, Data())).decode(using: decoder))?.isFailure == true)
    }

    @Test func decodingErrorIsWrappedInHTTPError() {
        guard case .failure(let e) = run(just(invalidJSON).decode(using: decoder)),
              case .decoding = e else {
            Issue.record("Expected .failure(.decoding)")
            return
        }
    }

    @Test func mapAfterDecode() {
        let p = just(personJSON).decode(using: decoder).map(\.name)
        #expect(run(p)?.successValue == "Alice")
    }
}

// MARK: - AnyPublisher: Encoding

@Suite("AnyPublisher — encode")
struct AnyPublisherEncodeTests {
    private let person  = Person(id: 1, name: "Alice")
    private let encoder = JSONEncoder().dataEncoder(for: Person.self)

    private func personPublisher(failure: EncodingError.Type = EncodingError.self) -> AnyPublisher<Person, EncodingError> {
        Just(person).setFailureType(to: EncodingError.self).eraseToAnyPublisher()
    }

    @Test func encodesValue() throws {
        let data = try #require(firstResult(of: personPublisher().encode(using: encoder))?.successValue)
        #expect(try JSONDecoder().decode(Person.self, from: data) == person)
    }

    @Test func encodesWithFactory() throws {
        let data = try #require(firstResult(of: personPublisher().encode(using: JSONEncoder()))?.successValue)
        #expect(try JSONDecoder().decode(Person.self, from: data) == person)
    }

    @Test func encodesWithMapError() throws {
        enum E: Error { case enc(EncodingError) }
        let pub = Just(person).setFailureType(to: E.self).eraseToAnyPublisher()
        let data = try #require(firstResult(of: pub.encode(using: encoder, mapError: E.enc))?.successValue)
        #expect(try JSONDecoder().decode(Person.self, from: data) == person)
    }

    @Test func encodesWithFactoryAndMapError() throws {
        enum E: Error { case enc(EncodingError) }
        let pub = Just(person).setFailureType(to: E.self).eraseToAnyPublisher()
        let data = try #require(firstResult(of: pub.encode(using: JSONEncoder(), mapError: E.enc))?.successValue)
        #expect(try JSONDecoder().decode(Person.self, from: data) == person)
    }
}

#endif

// MARK: - HTTPError

@Suite("HTTPError")
struct HTTPErrorTests {
    @Test func networkDescription() {
        #expect(HTTPError.network(URLError(.notConnectedToInternet)).description.hasPrefix("Network error:"))
    }

    @Test func badStatusDescription() {
        #expect(HTTPError.badStatus(404, Data()).description == "HTTP 404")
        #expect(HTTPError.badStatus(500, Data()).description == "HTTP 500")
    }

    @Test func decodingDescription() {
        let inner = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        #expect(HTTPError.decoding(inner).description.hasPrefix("Decoding error:"))
    }
}
