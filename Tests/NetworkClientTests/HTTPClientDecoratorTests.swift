// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
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

private func run(_ requester: HTTPRequester, _ request: URLRequest) async -> Result<(Data, HTTPURLResponse), HTTPError>? {
    await requester(request).firstResultTask().run()
}

/// A base requester returning a fixed 200 body, counting how many times it was actually called.
private final class SpyBase: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    let body: Data
    init(body: Data) { self.body = body }
    func requester() -> HTTPRequester {
        HTTPRequester { [self] request in
            lock.withLock { _calls += 1 }
            return makeResponse(request: request, status: 200, headers: ["X-Base": "yes"], body: body).publisher
        }
    }
}

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
}

// MARK: - RequestMatch

@Suite struct RequestMatchTests {
    @Test func methodAndPathAndQuery() {
        let m = .method("get") && .path("/users") && .query("page", "2")
        #expect(m(req("https://api.example.com/users?page=2")))
        #expect(!m(req("https://api.example.com/users?page=3")))
        #expect(!m(req("https://api.example.com/users?page=2", method: "POST")))
    }

    @Test func pathTolerantOfTrailingSlash() {
        #expect(RequestMatch.path("/users")(req("https://x.com/users/")))
        #expect(RequestMatch.path("/users")(req("https://x.com/users")))
    }

    @Test func hostPrefixRegexHeader() {
        #expect(RequestMatch.host("staging.x.com")(req("https://staging.x.com/a")))
        #expect(RequestMatch.pathPrefix("/api/v1")(req("https://x.com/api/v1/users")))
        #expect(RequestMatch.pathRegex("^/users/[0-9]+$")(req("https://x.com/users/42")))
        #expect(!RequestMatch.pathRegex("^/users/[0-9]+$")(req("https://x.com/users/abc")))
        #expect(RequestMatch.header("Authorization", "Bearer t")(req("https://x.com", headers: ["Authorization": "Bearer t"])))
    }

    @Test func combinators() {
        let staging = RequestMatch.host("staging.x.com") || .host("dev.x.com")
        #expect(staging(req("https://dev.x.com/a")))
        #expect((!RequestMatch.method("GET"))(req("https://x.com", method: "POST")))
        #expect(RequestMatch.all([.method("GET"), .pathPrefix("/a")])(req("https://x.com/a/b")))
        #expect(!RequestMatch.any([.host("a.com"), .host("b.com")])(req("https://x.com")))
    }
}

// MARK: - StubResponse composition

@Suite struct StubResponseTests {
    @Test func okDefaultsTo200Empty() {
        let r = StubResponse.ok().response(for: req("https://x.com"), incoming: .failure(.network(URLError(.badURL))))
        let (data, response) = try! r.get()
        #expect(response.statusCode == 200)
        #expect(data.isEmpty)
    }

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

    @Test func failureStub() {
        let r = StubResponse.failure(.network(URLError(.notConnectedToInternet)))
            .response(for: req("https://x.com"), incoming: StubResponse.seed(for: req("https://x.com")))
        #expect({ if case .failure = r { true } else { false } }())
    }
}

// MARK: - Override decorator

@Suite struct OverrideTests {
    @Test func matchingRequestIsOverriddenWithoutHittingBase() async {
        let spy = SpyBase(body: Data("real".utf8))
        let client = spy.requester().decorated(by: HTTPRequester.overriding([
            Rule(.path("/currencies"), respond: .ok(body: Data("[\"BRL\"]".utf8))),
        ]))
        let result = await run(client, req("https://x.com/currencies"))
        let (data, response) = try! result!.get()
        #expect(String(decoding: data, as: UTF8.self) == "[\"BRL\"]")
        #expect(response.statusCode == 200)
        #expect(spy.calls == 0) // short-circuited: base never called
    }

    @Test func nonMatchingRequestPassesThrough() async {
        let spy = SpyBase(body: Data("real".utf8))
        let client = spy.requester().decorated(by: HTTPRequester.overriding(when: .path("/mocked"), respond: .ok()))
        let result = await run(client, req("https://x.com/other"))
        let (data, response) = try! result!.get()
        #expect(String(decoding: data, as: UTF8.self) == "real")
        #expect(response.value(forHTTPHeaderField: "X-Base") == "yes")
        #expect(spy.calls == 1)
    }

    @Test func firstMatchWins() async {
        let client = SpyBase(body: Data()).requester().decorated(by: HTTPRequester.overriding([
            Rule(.pathPrefix("/a"), respond: .status(201)),
            Rule(.path("/a/b"), respond: .status(202)),
        ]))
        let result = await run(client, req("https://x.com/a/b"))
        #expect(try! result!.get().1.statusCode == 201)
    }

    @Test func delayPathDoesNotAlterValue() async {
        // ImmediateClock collapses the delay to zero deterministically — exercises the delay code
        // path (Hourglass owns the actual timing semantics) without a TestClock subscribe/advance race.
        let client = SpyBase(body: Data()).requester().decorated(by: HTTPRequester.overriding(
            [Rule(.any, respond: .ok(body: Data("done".utf8)) <> .withDelay(.seconds(5)))],
            clock: ImmediateClock()
        ))
        let result = await run(client, req("https://x.com"))
        #expect(String(decoding: try! result!.get().0, as: UTF8.self) == "done")
    }
}

// MARK: - Record + Replay round-trip

@Suite struct RecordReplayTests {
    @Test func recordThenReplayRoundTrips() async {
        let url = tempURL()
        let base = HTTPRequester { request in
            makeResponse(
                request: request,
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data("{\"ok\":1}".utf8)
            ).publisher
        }
        let store = RecordStore(url: url, encoder: JSONEncoder(), decoder: JSONDecoder())
        _ = await store.reset()

        // Record
        let recording = base.decorated(by: HTTPRequester.recording(to: store))
        _ = await run(recording, req("https://x.com/data"))
        let recorded = await store.all()
        #expect(recorded.count == 1)
        #expect(recorded.first?.statusCode == 200)
        #expect(recorded.first?.responseHeaders?["Content-Type"] == "application/json")

        // Replay
        let playback = RequestPlayback(exchanges: recorded)
        let replay = HTTPRequester { _ in Publisher.fail(.network(URLError(.badURL))) } // fallback should NOT be hit
            .decorated(by: HTTPRequester.replaying(playback))
        let result = await run(replay, req("https://x.com/data"))
        let (data, response) = try! result!.get()
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json") // headers replayed
        #expect(String(decoding: data, as: UTF8.self) == "{\"ok\":1}")
    }

    @Test func replayConsumesOnce() async {
        let a = RecordedExchange(method: "GET", url: "https://x.com/n", statusCode: 200, responseBody: Data("1".utf8))
        let b = RecordedExchange(method: "GET", url: "https://x.com/n", statusCode: 200, responseBody: Data("2".utf8))
        let playback = RequestPlayback(exchanges: [a, b])
        let replay = HTTPRequester { _ in Publisher.fail(.network(URLError(.badURL))) }
            .decorated(by: HTTPRequester.replaying(playback, fallback: .notFound))

        #expect(String(decoding: try! (await run(replay, req("https://x.com/n")))!.get().0, as: UTF8.self) == "1")
        #expect(String(decoding: try! (await run(replay, req("https://x.com/n")))!.get().0, as: UTF8.self) == "2")
        // third call: exhausted -> fallback 404
        #expect(try! (await run(replay, req("https://x.com/n")))!.get().1.statusCode == 404)
    }

    @Test func replayFallsBackToBaseWhenUnmatched() async {
        let playback = RequestPlayback(exchanges: [])
        let spy = SpyBase(body: Data("live".utf8))
        let replay = spy.requester().decorated(by: HTTPRequester.replaying(playback, fallback: .base))
        let result = await run(replay, req("https://x.com/unrecorded"))
        #expect(String(decoding: try! result!.get().0, as: UTF8.self) == "live")
        #expect(spy.calls == 1)
    }
}

// swiftlint:enable force_unwrapping force_try optional_data_string_conversion
