# Mocking, Recording & Replaying

Develop against endpoints that don't exist yet, force edge-case responses, and turn flaky end-to-end
tests into deterministic ones — all by composing pure decorators onto your HTTP client.

## Overview

A decorator is an `Endo<HTTPRequester>` — a pure, callable `(HTTPRequester) -> HTTPRequester`. Four are provided:

| Decorator | Purpose |
|---|---|
| ``HTTPRequester/overriding(_:)`` | Short-circuit matching requests with a canned ``StubResponse`` (no network). |
| ``HTTPRequester/recording(to:now:)`` | Tee every real exchange to a ``RecordStore`` on disk. |
| ``HTTPRequester/replaying(_:matching:fallback:)`` | Serve recorded responses from a ``RequestPlayback`` snapshot, once each. |
| ``HTTPRequester/delaying(_:when:clock:)`` | Add artificial latency to matching responses (injected clock). |

You apply one by calling it on a base — `overriding(rules)(base)` — and layer several by nesting
(`b(a(base))`), which keeps the order of execution explicit. They read against two shared atoms:
``RequestMatch`` (which request) and
``StubResponse`` (what response).

## Matching requests — ``RequestMatch``

Matching is a composable `(URLRequest) -> Bool`. Start specific, combine with `&&` / `||` / `!`:

```swift
.method("GET") && .path("/users") && .query("page", "2")   // GET /users?page=2
.host("staging.example.com") || .host("dev.example.com")   // either environment
.pathRegex("^/users/[0-9]+$")                              // /users/42 but not /users/me
!.header("X-Cache")                                        // requests without the cache header
```

Constructors: ``RequestMatch/method(_:)``, ``RequestMatch/host(_:)``, ``RequestMatch/path(_:)``
(trailing-slash tolerant), ``RequestMatch/pathPrefix(_:)``, ``RequestMatch/pathRegex(_:)``,
``RequestMatch/query(_:_:)``, ``RequestMatch/header(_:_:)``, ``RequestMatch/url(_:)``,
``RequestMatch/body(_:)``, ``RequestMatch/any``, ``RequestMatch/custom(_:)``.

## Building responses — ``StubResponse``

A response is an `Endo` over the `Result`, so you assemble one from small composable pieces on top of
sensible defaults (**200**, no headers, empty body) — set only what you need:

```swift
.ok(body: json)                                          // 200 + body
.ok() <> .withStatus(201) <> .withHeader("ETag", "\"v1\"") // build it up piece by piece
.json(User(id: 1), status: 200, encoder: JSONEncoder())   // encode a value + Content-Type
.failure(.network(URLError(.notConnectedToInternet)))     // simulate a transport error
```

Latency is a *separate* concern (it's about timing, not the response value) — compose the
``HTTPRequester/delaying(_:when:clock:)`` decorator when you want a slow response.

## Scenario 1 — Override: mock an endpoint that isn't built yet

The backend team has agreed the contract for `GET /currencies` but hasn't shipped it. You want to
build and demo the client **now**. Override it with the agreed shape — no network, no waiting:

```swift
let mocks = HTTPRequester.overriding([
    Rule(.method("GET") && .path("/currencies"),
         respond: .json(["MXN", "ARS", "COP", "BRL"], encoder: JSONEncoder())),
])

let client = mocks(URLSession.shared.httpRequester)
// GET /currencies → your canned JSON; every other request hits the real network.
```

The same tool forces **edge cases** your UI must handle but the server won't produce on demand — an
empty list, a 500, a timeout, or a slow response to test your spinner:

```swift
// A mock per condition:
HTTPRequester.overriding([
    Rule(.path("/currencies"), respond: .ok(body: Data("[]".utf8))),              // empty state
    Rule(.path("/profile"),    respond: .status(500, body: Data("boom".utf8))),   // error state
    Rule(.path("/feed"),       respond: .failure(.network(URLError(.timedOut)))), // transport failure
])

// …and slow /slow down by three seconds to exercise the spinner (a separate decorator wrapping the mock):
HTTPRequester.delaying(.seconds(3), when: .path("/slow"), clock: ContinuousClock())(
    HTTPRequester.overriding([Rule(.path("/slow"), respond: .ok(body: page))])(base)
)
```

Rules are first-match-wins; unmatched requests pass straight through to the wrapped client.

## Scenario 2 — Record & Replay: deterministic tests over flaky shared staging

Your integration / e2e suite runs against a **real staging server**. Staging is a shared public
resource — other teams change data, occasionally break it, and the same call can return different
things at different times. Running the suite against it is slow and flaky.

The fix: **record once, replay forever, re-record on a cadence.**

**Record** a session against real staging (do this once, then ~weekly to keep the snapshot fresh):

```swift
let store = RecordStore(
    url: snapshotURL,                 // committed alongside the test
    encoder: JSONEncoder(),           // or Plist/XML/YAML — any DataEncoderFactory
    decoder: JSONDecoder()
)
await store.reset()                   // start the session clean

let recordingClient = HTTPRequester.recording(to: store, now: { Date() })(liveStagingClient)  // clock injected at the boundary
// run the suite once through `recordingClient`; every exchange is captured to `snapshotURL`.
```

`RecordStore` is an `actor`, so parallel requests can't corrupt the file (no read-modify-write race),
and it **surfaces** write failures instead of swallowing them.

**Replay** the snapshot in CI — multiple times a day, deterministically, with no network:

```swift
guard let playback = RequestPlayback.load(url: snapshotURL, decoder: JSONDecoder()) else { return }
let noNetwork = HTTPRequester { _ in Publisher.fail(.network(URLError(.badURL))) }
let testClient = HTTPRequester.replaying(playback, fallback: .notFound)(noNetwork)
// every recorded call replays its exact status, headers and body — same result every run.
```

### The same endpoint returning different responses over a test

Replay is **consume-once**: for a given matcher, the *1st* time it hits serves the *1st* recorded
match, the *2nd* hit the *2nd*, and so on — matcher, then index. That's exactly what a realistic
scenario needs. Imagine a test that submits a job and polls until it's done:

```
POST /jobs           → 202 { "id": "j1" }
GET  /jobs/j1/status → 200 { "state": "pending" }     (1st poll)
GET  /jobs/j1/status → 200 { "state": "pending" }     (2nd poll)
GET  /jobs/j1/status → 200 { "state": "done" }        (3rd poll)
```

Recorded in that order, replay serves the three `GET /jobs/j1/status` responses in sequence — the
poll loop sees `pending → pending → done` and terminates, deterministically, every run. When the
snapshot is exhausted for a matcher, the `fallback` takes over (a synthetic 404, a failure, or the
wrapped client — see ``ReplayFallback``).

### Cadence

- **Daily / every CI run:** replay the snapshot. Fast, deterministic, isolated from staging.
- **Weekly (or when the contract changes):** re-run through the recording client against real
  staging and commit the refreshed snapshot. A drift between the snapshot and reality surfaces as a
  test change in review — exactly where you want it.

## Composing them

Decorators are callable values; **nest** them to layer. The nesting order *is* the execution order —
innermost runs first — so it's never ambiguous which wraps which. Put `recording` on the *outside* of
`overriding` so mocked responses are captured too:

```swift
// Capture a session that also includes local mocks (recording wraps overriding wraps the live client):
let client = HTTPRequester.recording(to: store, now: { Date() })(
    HTTPRequester.overriding(rules)(
        URLSession.shared.httpRequester
    )
)
```
