# Mocking, Recording & Replaying

Develop against endpoints that don't exist yet, force edge-case responses, and turn flaky end-to-end
tests into deterministic ones — all by composing pure decorators onto ``HTTPClient``.

## Overview

A decorator is an `Endo<HTTPClient>` — a pure, callable `(HTTPClient) -> HTTPClient`. You apply one by
calling it on a base client, and layer several by **nesting** (`b(a(base))`) — the nesting order *is*
the execution order, so which decorator wraps which is never ambiguous.

| Decorator | Purpose |
|---|---|
| `override(on:use:)` | Route matching requests to another client (typically a `.const` mock). |
| ``HTTPClient/record(to:now:)`` | Tee every real exchange to a ``RecordStore`` on disk. |
| ``HTTPClient/playback(_:matching:)`` | Serve recorded responses from a ``RequestPlayback`` snapshot, once each. |
| ``HTTPClient/delay(_:when:clock:)`` | Add artificial latency to matching responses (injected clock). |

Clients are built with ``HTTPClient/live(session:)`` (real network) or `HTTPClient.const`
(a fixed response — the mock). Two shared atoms drive the decorators: ``RequestMatch`` (which request)
and ``StubResponse`` (what response).

## Matching requests — ``RequestMatch``

A composable `(URLRequest) -> Bool`. Start specific, combine with `&&` / `||` / `!`:

```swift
.method("GET") && .path("/users") && .query("page", "2")   // GET /users?page=2
.host("staging.example.com") || .host("dev.example.com")   // either environment
.pathRegex("^/users/[0-9]+$")                              // /users/42 but not /users/me
```

## Building responses — ``StubResponse``

A response is composed from small pieces on top of sensible defaults (**200**, no headers, empty body):

```swift
.ok(body: json)                                          // 200 + body
.ok() <> .withStatus(201) <> .withHeader("ETag", "\"v1\"") // build it up piece by piece
.json(User(id: 1), encoder: JSONEncoder())                // encode a value + Content-Type
.failure(.network(URLError(.notConnectedToInternet)))     // simulate a transport error
```

Wrap one in a client with `.const(...)`, or return a fixed `Result` with `.const(result)`. Latency is
separate — compose ``HTTPClient/delay(_:when:clock:)``.

## Scenario 1 — Override: mock an endpoint that isn't built yet

The backend team agreed the contract for `GET /currencies` but hasn't shipped it. Build against it
**now** — route that one request to a mock, everything else to the live network:

```swift
let client = HTTPClient.override(
    on: .method("GET") && .path("/currencies"),
    use: .const(.json(["MXN", "ARS", "COP", "BRL"], encoder: JSONEncoder()))
)(HTTPClient.live(session: .shared))
```

The same tool forces **edge cases** the server won't produce on demand — an empty list, a 500, a
timeout — by nesting overrides (the outer is checked first):

```swift
let client =
    HTTPClient.override(on: .path("/feed"),    use: .const(.failure(.network(URLError(.timedOut)))))(
    HTTPClient.override(on: .path("/profile"), use: .const(.status(500, body: Data("boom".utf8))))(
    HTTPClient.override(on: .path("/list"),    use: .const(.ok(body: Data("[]".utf8))))(
        HTTPClient.live(session: .shared)
    )))
```

A **request-derived** override can build the response from the request itself:

```swift
HTTPClient.override(on: .path("/echo")) { request in
    .const(.ok() <> .withHeaders(request.allHTTPHeaderFields ?? [:]))
}(base)
```

## Scenario 2 — Record & Replay: deterministic tests over flaky shared staging

Your integration / e2e suite runs against a **real staging server** — a shared public resource that
other teams change and occasionally break. Running the suite against it is slow and flaky. The fix:
**record once, replay forever, re-record on a cadence.**

**Record** a session against real staging (once, then ~weekly to keep the snapshot fresh):

```swift
let store = RecordStore(
    url: snapshotURL,                 // committed alongside the test
    encoder: JSONEncoder(),           // or Plist/XML/YAML — any DataEncoderFactory
    decoder: JSONDecoder()
)
await store.reset()

let recordingClient = HTTPClient.record(to: store, now: { Date() })(   // clock injected at the boundary
    HTTPClient.live(session: .shared)
)
// run the suite once through `recordingClient`; every exchange is captured to `snapshotURL`.
```

`RecordStore` is an `actor`, so parallel requests can't corrupt the file (no read-modify-write race),
and it **surfaces** write failures instead of swallowing them. Binary IO is injected via
``BinaryReader`` / ``BinaryWriter`` (defaulting to the filesystem).

**Replay** the snapshot in CI — deterministically, with no network. Unmatched requests fall through to
the base client, so nest a `.const(.status(404))` for strict replay:

```swift
guard let source = RequestPlayback.load(url: snapshotURL, decoder: JSONDecoder()) else { return }
let testClient = HTTPClient.playback(source)(HTTPClient.const(.status(404)))
// every recorded call replays its exact status, headers and body — same result every run.
```

### The same endpoint returning different responses over a test

Replay is **consume-once**: for a given matcher, the *1st* hit serves the *1st* recorded match, the
*2nd* the *2nd*, and so on — matcher, then index. So a test that submits a job and polls until done:

```
POST /jobs           → 202 { "id": "j1" }
GET  /jobs/j1/status → 200 { "state": "pending" }     (1st poll)
GET  /jobs/j1/status → 200 { "state": "pending" }     (2nd poll)
GET  /jobs/j1/status → 200 { "state": "done" }        (3rd poll)
```

Recorded in that order, replay serves the three `GET /jobs/j1/status` responses in sequence — the poll
loop sees `pending → pending → done` and terminates, deterministically, every run.

### Cadence

- **Daily / every CI run:** replay the snapshot. Fast, deterministic, isolated from staging.
- **Weekly (or when the contract changes):** re-run through the recording client against real staging
  and commit the refreshed snapshot. Drift surfaces as a test change in review — where you want it.

## Composing them

Decorators are callable values; **nest** to layer. Put `record` on the *outside* of `override` so
mocked responses are captured too:

```swift
let client = HTTPClient.record(to: store, now: { Date() })(
    HTTPClient.override(on: .path("/mocked"), use: .const(.ok(body: json)))(
        HTTPClient.live(session: .shared)
    )
)
```
