// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import Hourglass
@testable import NetworkClient
import ReactiveConcurrency
import Testing

// Test code legitimately uses force unwraps/tries on known-good fixtures and non-failable UTF-8
// decoding for assertions.
// swiftlint:disable force_unwrapping force_try optional_data_string_conversion

// MARK: - Helpers

private func req(_ url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> URLRequest {
    var r = URLRequest(url: URL(string: url)!)
    r.httpMethod = method
    r.httpBody = body
    for (k, v) in headers {
        r.setValue(v, forHTTPHeaderField: k)
    }
    return r
}

private func run(_ client: HTTPClient, _ request: URLRequest) async -> Result<(Data, HTTPURLResponse), HTTPError>? {
    await client(request).firstResultTask().run()
}

/// A base client returning a fixed 200 body, counting how many times it was actually called.
private final class SpyBase: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    let body: Data
    init(body: Data) { self.body = body }
    func client() -> HTTPClient {
        HTTPClient { [self] request in
            lock.withLock { _calls += 1 }
            return makeResponse(request: request, status: 200, headers: ["X-Base": "yes"], body: body).publisher
        }
    }
}

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
}

// MARK: - HTTPClient basics + pipeline

@Suite struct HTTPClientTests {
    @Test func constResultAlwaysReturnsIt() async {
        let client = HTTPClient.const(makeResponse(url: URL(string: "https://x.com")!, status: 201, headers: [:], body: Data("hi".utf8)))
        let (data, response) = try! (await run(client, req("https://x.com/anything")))!.get()
        #expect(response.statusCode == 201)
        #expect(String(decoding: data, as: UTF8.self) == "hi")
    }

    @Test func constStubBuildsResponse() async {
        let client = HTTPClient.const(.ok(body: Data("body".utf8)) <> .withStatus(202) <> .withHeader("X-Test", "1"))
        let (data, response) = try! (await run(client, req("https://x.com")))!.get()
        #expect(response.statusCode == 202)
        #expect(response.value(forHTTPHeaderField: "X-Test") == "1")
        #expect(String(decoding: data, as: UTF8.self) == "body")
    }

    @Test func validateStatusCodePassesOn2xxFailsOtherwise() async {
        let ok = HTTPClient.const(makeResponse(url: URL(string: "https://x.com")!, status: 200, headers: [:], body: Data("ok".utf8)))
        let okResult = await ok(req("https://x.com")).validateStatusCode().firstResultTask().run()
        #expect(String(decoding: try! okResult!.get(), as: UTF8.self) == "ok")

        let bad = HTTPClient.const(makeResponse(url: URL(string: "https://x.com")!, status: 404, headers: [:], body: Data("no".utf8)))
        let badResult = await bad(req("https://x.com")).validateStatusCode().firstResultTask().run()
        #expect({ if case .failure(.badStatus(404, _)) = badResult! { true } else { false } }())
    }

    @Test func decodeParsesJSON() async throws {
        struct Payload: Codable, Sendable, Equatable { let x: Int }
        let body = try JSONEncoder().encode(Payload(x: 5))
        let client = HTTPClient.const(makeResponse(url: URL(string: "https://x.com")!, status: 200, headers: [:], body: body))
        let result = await client(req("https://x.com"))
            .validateStatusCode()
            .decode(using: JSONDecoder(), type: Payload.self)
            .firstResultTask()
            .run()
        #expect(try! result!.get() == Payload(x: 5))
    }
}

// MARK: - RequestMatch

@Suite struct RequestMatchTests {
    @Test func methodAndPathAndQuery() {
        let m = .method("get") && .path("/users") && .query("page", "2")
        #expect(m(req("https://api.example.com/users?page=2")))
        #expect(!m(req("https://api.example.com/users?page=3")))
        #expect(!m(req("https://api.example.com/users?page=2", method: "POST")))
    }

    @Test func hostPrefixRegexCombinators() {
        #expect(RequestMatch.pathPrefix("/api/v1")(req("https://x.com/api/v1/users")))
        #expect(RequestMatch.pathRegex("^/users/[0-9]+$")(req("https://x.com/users/42")))
        #expect(!RequestMatch.pathRegex("^/users/[0-9]+$")(req("https://x.com/users/abc")))
        let staging = RequestMatch.host("staging.x.com") || .host("dev.x.com")
        #expect(staging(req("https://dev.x.com/a")))
        #expect((!RequestMatch.method("GET"))(req("https://x.com", method: "POST")))
    }
}

// MARK: - StubResponse composition

@Suite struct StubResponseTests {
    @Test func composedResponse() {
        let stub = StubResponse.ok(body: Data("hi".utf8)) <> .withStatus(201) <> .withHeader("Content-Type", "text/plain")
        let (data, response) = try! stub.response(for: req("https://x.com"), incoming: StubResponse.seed(for: req("https://x.com"))).get()
        #expect(response.statusCode == 201)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/plain")
        #expect(String(decoding: data, as: UTF8.self) == "hi")
    }

    @Test func jsonEncodesBody() throws {
        struct Payload: Codable, Sendable, Equatable { let x: Int }
        let stub = StubResponse.json(Payload(x: 7), status: 200, encoder: JSONEncoder())
        let (data, response) = try stub.response(for: req("https://x.com"), incoming: .failure(.network(URLError(.badURL)))).get()
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode(Payload.self, from: data) == Payload(x: 7))
    }
}

// MARK: - Override decorator

@Suite struct OverrideTests {
    @Test func matchingRequestUsesTheOverrideWithoutHittingBase() async {
        let spy = SpyBase(body: Data("real".utf8))
        let client = HTTPClient.override(on: .path("/currencies"), use: .const(.ok(body: Data("[\"BRL\"]".utf8))))(spy.client())
        let (data, response) = try! (await run(client, req("https://x.com/currencies")))!.get()
        #expect(String(decoding: data, as: UTF8.self) == "[\"BRL\"]")
        #expect(response.statusCode == 200)
        #expect(spy.calls == 0)
    }

    @Test func nonMatchingRequestPassesThrough() async {
        let spy = SpyBase(body: Data("real".utf8))
        let client = HTTPClient.override(on: .path("/mocked"), use: .const(.ok()))(spy.client())
        let (data, response) = try! (await run(client, req("https://x.com/other")))!.get()
        #expect(String(decoding: data, as: UTF8.self) == "real")
        #expect(response.value(forHTTPHeaderField: "X-Base") == "yes")
        #expect(spy.calls == 1)
    }

    @Test func outerOverrideWinsWhenNested() async {
        let base = SpyBase(body: Data()).client()
        let inner = HTTPClient.override(on: .path("/a/b"), use: .const(.status(202)))(base)
        let client = HTTPClient.override(on: .pathPrefix("/a"), use: .const(.status(201)))(inner)
        #expect(try! (await run(client, req("https://x.com/a/b")))!.get().1.statusCode == 201)
    }

    @Test func requestDerivedOverrideEchoesHeaders() async {
        let base = SpyBase(body: Data()).client()
        let client = HTTPClient.override(on: .path("/echo")) { request in
            .const(.ok() <> .withHeaders(request.allHTTPHeaderFields ?? [:]))
        }(base)
        let (_, response) = try! (await run(client, req("https://x.com/echo", headers: ["X-In": "v"])))!.get()
        #expect(response.value(forHTTPHeaderField: "X-In") == "v")
    }
}

// MARK: - Delay

@Suite struct DelayTests {
    @Test func delayPassesValueThroughOnImmediateClock() async {
        // ImmediateClock collapses the delay deterministically — exercises the delay path without a
        // TestClock subscribe/advance race.
        let base = SpyBase(body: Data("done".utf8)).client()
        let client = HTTPClient.delay(.seconds(5), clock: ImmediateClock())(base)
        #expect(String(decoding: try! (await run(client, req("https://x.com")))!.get().0, as: UTF8.self) == "done")
    }
}

// MARK: - Record + Playback

@Suite struct RecordPlaybackTests {
    @Test func recordThenPlaybackRoundTrips() async {
        let url = tempURL()
        let base = HTTPClient { request in
            makeResponse(
                request: request,
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data("{\"ok\":1}".utf8)
            ).publisher
        }
        let store = RecordStore(url: url, encoder: JSONEncoder(), decoder: JSONDecoder())
        _ = await store.reset()

        let recording = HTTPClient.record(to: store)(base)
        _ = await run(recording, req("https://x.com/data"))
        let recorded = await store.all()
        #expect(recorded.count == 1)
        #expect(recorded.first?.responseHeaders?["Content-Type"] == "application/json")

        let source = RequestPlayback(exchanges: recorded)
        let playback = HTTPClient.playback(source)(HTTPClient.const(.status(404)))
        let (data, response) = try! (await run(playback, req("https://x.com/data")))!.get()
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: data, as: UTF8.self) == "{\"ok\":1}")
    }

    @Test func playbackConsumesOnceThenFallsThrough() async {
        let a = RecordedExchange(method: "GET", url: "https://x.com/n", statusCode: 200, responseBody: Data("1".utf8))
        let b = RecordedExchange(method: "GET", url: "https://x.com/n", statusCode: 200, responseBody: Data("2".utf8))
        let source = RequestPlayback(exchanges: [a, b])
        let client = HTTPClient.playback(source)(HTTPClient.const(.status(404)))

        #expect(String(decoding: try! (await run(client, req("https://x.com/n")))!.get().0, as: UTF8.self) == "1")
        #expect(String(decoding: try! (await run(client, req("https://x.com/n")))!.get().0, as: UTF8.self) == "2")
        #expect(try! (await run(client, req("https://x.com/n")))!.get().1.statusCode == 404)
    }

    @Test func playbackFallsThroughToBaseWhenUnmatched() async {
        let source = RequestPlayback(exchanges: [])
        let spy = SpyBase(body: Data("live".utf8))
        let client = HTTPClient.playback(source)(spy.client())
        #expect(String(decoding: try! (await run(client, req("https://x.com/unrecorded")))!.get().0, as: UTF8.self) == "live")
        #expect(spy.calls == 1)
    }
}

// swiftlint:enable force_unwrapping force_try optional_data_string_conversion
