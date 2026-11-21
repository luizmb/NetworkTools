# NetworkTools

[![CI](https://github.com/luizmb/NetworkTools/actions/workflows/ci.yml/badge.svg)](https://github.com/luizmb/NetworkTools/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-online-blue)](https://ios.lu/NetworkTools)
[![Swift 6.3+](https://img.shields.io/badge/swift-6.3%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

**[→ Full API Documentation](https://ios.lu/NetworkTools)**

A suite of Swift packages for HTML templating, HTTP client networking, and HTTP server hosting. Built on functional programming principles using [`FP`](https://github.com/luizmb/FP): every public API uses `Reader` for dependency injection, `Result` for error handling, [ReactiveConcurrency](https://github.com/luizmb/ReactiveConcurrency)'s `Publisher` (a cold, lazy, composable async stream) for async work, and `FunctionWrapper` for composable function types. No Combine, no force-unwraps, no `fatalError`, no silent failures.

**Platforms:** macOS 13+, iOS 16+, tvOS 16+, watchOS 9+

---

## Packages

- [Core](#core) — codec layer (`Convert`, `DataEncoder`/`DataDecoder` + factories) shared by the other packages
- [HTMLTemplating](#htmltemplating) — file-based HTML template engine with `{{}}` directives
- [Multipeer](#multipeer) — `MultipeerConnectivity` wrapper exposing advertiser/browser/session events as `Publisher`s
- [NetworkClient](#networkclient) — composable HTTP client: one `HTTPClient` type + pure decorators for mocking, recording, and replaying
- [NetworkServer](#networkserver) — embedded NIO-backed HTTP server with a typed functional routing DSL
- [WebSocketClient](#websocketclient) — full-duplex WebSocket client exposing a `WebSocketConnection` with `Publisher`-based receive/send; `WebSocketClientNIO` opens one over swift-nio
- [BonjourService](#bonjourservice) — Bonjour discovery and advertising exposed as `Publisher` streams
- [MQTT](#mqtt) — MQTT 3.1.1 and 5: packet model and codec, client (`MQTTClient`), broker (`MQTTBroker`) and bridge (`MQTTBridge`) as pure state machines, and one target per transport (`MQTTNWConnection`, `MQTTNIO`, `MQTTWebSocket`)

---

## Platform Support

What **works** on each platform. Every ✅ is built and tested in CI on that platform (macOS, Linux,
Android on an emulator, Windows); ❌ means the product does nothing there.

| Product | Apple | Linux | Android | Windows | Notes |
|---|:---:|:---:|:---:|:---:|---|
| **Core** | ✅ | ✅ | ✅ | ✅ | Pure `FP` + Foundation |
| **HTMLTemplating** | ✅ | ✅ | ✅ | ✅ | Pure `FP` + Foundation |
| **NetworkClient** | ✅ | ✅ | ✅ | ✅ | `URLSession` (`FoundationNetworking` off Apple) |
| **NetworkServer** | ✅ | ✅ | ✅ | ❌ | swift-nio; `NIOPosix` has no Windows support |
| **WebSocketClient** | ✅ | ✅ | ✅ | ❌ | `URLSessionWebSocketTask` on Apple; anywhere else through `WebSocketClientNIO` |
| **WebSocketClientNIO** | ✅ | ✅ | ✅ | ❌ | swift-nio WebSocket (`ws://`) |
| **Multipeer** | ✅ | ❌ | ❌ | ❌ | `MultipeerConnectivity` |
| **BonjourService** | ✅ | ❌ | ❌ | ❌ | `Network` / `NetService` |
| **MQTT** | ✅ | ✅ | ✅ | ✅ | Packet model, codec, topic matching — pure |
| **MQTTClient** | ✅ | ✅ | ✅ | ❌ | Connecting needs a transport below; none runs on Windows yet |
| **MQTTBroker** | ✅ | ✅ | ✅ | ❌ | Accepting needs a listener below; none runs on Windows yet |
| **MQTTBridge** | ✅ | ✅ | ✅ | ❌ | Two client sessions |
| **MQTTNWConnection** | ✅ | ❌ | ❌ | ❌ | `Network.framework` client and listener |
| **MQTTNIO** | ✅ | ✅ | ✅ | ❌ | swift-nio TCP client and listener, WebSocket listener |
| **MQTTWebSocket** | ✅ | ✅ | ✅ | ❌ | URLSession on Apple, `WebSocketClientNIO` everywhere it runs |

Products marked ❌ still compile on that platform (their sources are `#if canImport(...)` gated), so
a cross-platform package can depend on them without conditional dependencies.

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/NetworkTools.git", from: "0.9.0")
```

Add individual products to your targets as needed:

```swift
.product(name: "Core",            package: "NetworkTools"),
.product(name: "HTMLTemplating",  package: "NetworkTools"),
.product(name: "NetworkClient",   package: "NetworkTools"),
.product(name: "NetworkServer",   package: "NetworkTools"),
.product(name: "WebSocketClient", package: "NetworkTools"),
.product(name: "WebSocketClientNIO", package: "NetworkTools"),
.product(name: "BonjourService",  package: "NetworkTools"),
.product(name: "MQTT",            package: "NetworkTools"),
.product(name: "MQTTClient",      package: "NetworkTools"),
.product(name: "MQTTBroker",      package: "NetworkTools"),
.product(name: "MQTTBridge",      package: "NetworkTools"),
.product(name: "MQTTNWConnection", package: "NetworkTools"),
.product(name: "MQTTNIO",         package: "NetworkTools"),
.product(name: "MQTTWebSocket",   package: "NetworkTools"),
```

---

## HTMLTemplating

A lightweight template engine that resolves `{{variables}}`, loops, conditionals, and includes. The fragment directory is threaded as a `Reader` environment — no stored properties, no singletons.

### Core types

```swift
public struct HTMLEnvironment {
    // Resolves a filename to a URL, or nil if not found.
    // All files use the .template extension: find("row.template") for fragments,
    // find("index.template") for top-level templates.
    public let find: (String) -> URL?
    // Reads a URL's contents, returning an error on failure.
    public let readFile: (URL) -> Result<String, Error>

    // Designated init — supply both for fully custom behaviour.
    public init(find: @escaping (String) -> URL?, readFile: @escaping (URL) -> Result<String, Error>)

    // Direct filesystem: appends the filename to path, reads via String(contentsOf:encoding:).
    public static func live(path: String) -> Self

    // Bundle-based: calls Bundle.url(forResource:withExtension:"template"),
    // reads via String(contentsOf:encoding:).
    public static func live(bundle: Bundle) -> Self

    // Testing: find returns a synthetic URL, readFile always succeeds with the given string.
    public static func mockSuccess(contents: String) -> Self

    // Testing: find returns a synthetic URL, readFile always fails with the given error.
    public static func mockFailure(error: Error) -> Self
}
```

All IO flows through the environment. Neither `render` nor `loadTemplate` performs IO directly.

```swift
// A template context: keys map to strings, booleans, or lists of sub-contexts.
public typealias Context = [String: TemplateValue]

public indirect enum TemplateValue {
    case string(String)
    case bool(Bool)
    case list([Context])
}

public enum TemplateError: Error {
    case notFound(String)           // template/fragment file not found
    case readError(String, Error)   // I/O error reading the file
}
```

### `render`

```swift
func render(_ template: String, _ context: Context) -> ReaderTResult<HTMLEnvironment, TemplateError, String>
```

The entry point. Returns a `ReaderTResult` stack (wrapping `Reader<HTMLEnvironment, Result<String, TemplateError>>`); leave with `.rawValue` and run it with an `HTMLEnvironment`.

```swift
let env = HTMLEnvironment.live(path: "/path/to/templates")

let result = render("Hello, {{name}}!", ["name": .string("World")])
    .rawValue.runReader(env)

// result == .success("Hello, World!")
```

### Variable substitution — `{{key}}`

Replaced with the string value of the key, or an empty string if the key is missing or is a list.

```swift
let template = "<title>{{title}}</title><p>{{body}}</p>"
let ctx: Context = [
    "title": .string("My Page"),
    "body":  .string("Welcome!"),
]
let html = try render(template, ctx).rawValue.runReader(env).get()
// "<title>My Page</title><p>Welcome!</p>"
```

Booleans render as `"true"` or `"false"`:

```swift
render("Active: {{active}}", ["active": .bool(true)]).rawValue.runReader(env)
// .success("Active: true")
```

### Loops — `{{#each key fragmentName}}`

Renders a fragment file once per item in a list, giving each iteration its own isolated sub-context.

```swift
// fragments/row.html.template:
// <li>{{name}} — {{score}}</li>

let ctx: Context = [
    "players": .list([
        ["name": .string("Alice"), "score": .string("42")],
        ["name": .string("Bob"),   "score": .string("37")],
    ])
]

let template = "<ul>{{#each players row}}</ul>"
let html = try render(template, ctx).rawValue.runReader(env).get()
// "<ul><li>Alice — 42</li><li>Bob — 37</li></ul>"
```

An empty list produces no output; a missing key is silently skipped.

### Conditionals — `{{#if key fragmentName}}`

Renders a fragment if the key is truthy (non-empty string, `true`, or non-empty list).

```swift
// fragments/badge.html.template:
// <span class="admin">Admin</span>

let template = "<p>{{username}}{{#if isAdmin badge}}</p>"
let ctx: Context = [
    "username": .string("alice"),
    "isAdmin":  .bool(true),
]
let html = try render(template, ctx).rawValue.runReader(env).get()
// "<p>alice<span class=\"admin\">Admin</span></p>"
```

Falsy values (empty string, `false`, empty list, missing key) produce no output.

### Includes — `{{#include fragmentName}}`

Inserts another fragment file inline, passing the current context through.

```swift
// fragments/header.html.template:
// <header><h1>{{siteName}}</h1></header>

// fragments/footer.html.template:
// <footer>© {{year}}</footer>

let template = """
{{#include header}}
<main>{{content}}</main>
{{#include footer}}
"""
let ctx: Context = [
    "siteName": .string("My App"),
    "content":  .string("<p>Hello</p>"),
    "year":     .string("2025"),
]
let html = try render(template, ctx).rawValue.runReader(env).get()
```

Includes compose freely — a fragment can itself contain `#include`, `#each`, and `#if` directives. Errors propagate outward through the `Result`.

### HTML escaping

```swift
esc("<script>alert('xss')</script>")
// "&lt;script&gt;alert('xss')&lt;/script&gt;"

escAttr(#"say "hello""#)
// "say &quot;hello&quot;"
```

`esc` escapes `&`, `<`, `>`. `escAttr` additionally escapes `"` for use inside HTML attributes.

### Template loader

`loadTemplate` reads a named `.template` file via the environment and returns the same `ReaderTResult` stack as `render`. Chain them with `>>-` so the environment is injected once and a load failure skips the render:

```swift
let ctx: Context = ["title": .string("Home"), "body": .string("<p>Hello</p>")]

// >>- is the ReaderTResult bind: threads the Result error automatically.
let page = loadTemplate("index") >>- { source in render(source, ctx) }

// Direct filesystem:
let html = page.rawValue.runReader(.live(path: "/app/templates"))

// Bundle:
let html = page.rawValue.runReader(.live(bundle: .main))

// Testing — no filesystem, no bundle:
let html = page.rawValue.runReader(.mockSuccess(contents: "<p>{{body}}</p>"))
```

### Composing with Reader

Because `render` reads its environment, you can swap the environment entirely without touching the template logic:

```swift
let pageReader: ReaderTResult<HTMLEnvironment, TemplateError, String> =
    render("{{#include layout}}", [
        "title":   .string("Dashboard"),
        "content": .string(bodyHTML),
    ])

// Production: filesystem-based.
let prodHTML = pageReader.rawValue.runReader(.live(path: "/app/templates"))
// Or bundle-based:
// let prodHTML = pageReader.rawValue.runReader(.live(bundle: .main))

// Testing: every fragment load succeeds with a fixed string.
let testHTML = pageReader.rawValue.runReader(.mockSuccess(contents: "<html>{{content}}</html>"))

// Testing: every fragment load fails — verifies error propagation.
let failHTML = pageReader.rawValue.runReader(.mockFailure(error: URLError(.fileDoesNotExist)))
```

All IO is fully contained in the environment — `render` never touches the filesystem directly.

---

## Core

Shared building blocks used by the other packages — the codec layer (`Convert`, `DataEncoder`/`DataDecoder`, and their factories). The `Loading<Success, Failure>` lifecycle enum used to live here; it now lives in [FP's `DataStructure` module](https://github.com/luizmb/FP/blob/main/docs/types/Loading.md) (from `v1.7.0` onwards) so any project can use it. Add `import DataStructure` to access it.

### `Convert<Input, Output, Failure>`

`Convert<Input, Output, Failure>` is a `FunctionWrapper` around `(Input) -> Result<Output, Failure>`. It is a reusable, composable fallible conversion as a first-class value, supporting the full Functor / Applicative / Monad hierarchy.

Concrete typealiases pin the type parameters for common uses:

```swift
// Data -> Result<D, DecodingError>
public typealias DataDecoder<D: Decodable> = Convert<Data, D, DecodingError>

// I -> Result<Data, EncodingError>
public typealias DataEncoder<I: Encodable> = Convert<I, Data, EncodingError>

// [String: String] -> Result<D, DecodingError>  (used by NetworkServer routing)
public typealias DictionaryDecoder<D: Decodable> = Convert<[String: String], D, DecodingError>
```

```swift
let userDecoder: DataDecoder<User>   = JSONDecoder().dataDecoder(for: User.self)
let albumEncoder: DataEncoder<Album> = JSONEncoder().dataEncoder(for: Album.self)

// Call directly:
let result: Result<User, DecodingError>  = userDecoder(jsonData)
let encoded: Result<Data, EncodingError> = albumEncoder(myAlbum)
```

### `DataDecoderFactory` / `DataEncoderFactory`

Protocols satisfied by `JSONDecoder` / `JSONEncoder` (and any custom codec). They let you inject the codec as a dependency rather than constructing it inline.

```swift
func makeDecoder() -> DataDecoderFactory {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}
```

### `Convert` — contravariant functor

`contramap` maps over the *input* type, adapting a `Convert<Input, Output, Failure>` to accept a different input by pre-processing it before the conversion runs:

```swift
let userDecoder: DataDecoder<User> = JSONDecoder().dataDecoder(for: User.self)

// Adapt to accept String instead of Data:
let stringDecoder: Convert<String, User, DecodingError> =
    userDecoder.contramap { Data($0.utf8) }
```

> Decoding/encoding values flowing through a `Publisher` lives with the client that produces them — see NetworkClient's `Publisher.validateStatusCode()` / `.decode(using:)`.

### Binary codecs — `ByteParser` / `ByteEncoder`

Building blocks for binary wire formats, shared by every protocol package (MQTT today; mDNS, PTP/IP, MIDI SysEx… later).

`ByteParser<A, Failure>` is FP's `StatefulTResult` over `ArraySlice<UInt8>` — a parser monad with every FP operator — plus byte primitives (big/little-endian integers, variable-length integers, UTF-8) and combinators (`ByteParsers.isolate`, `manyUntilEnd`, `count`, `optional`, backtracking `<|>`):

```swift
typealias P<A: Sendable> = BinaryParser<A>

let string: P<String> = P<UInt16>.integer(.big) >>- { P<String>.utf8(count: Int($0)) }
string.parseAll([0x00, 0x02, 0x68, 0x69])   // .success("hi")
```

`ByteEncoder<A, Failure>` is `Convert<A, [UInt8], Failure>`. `Convert` is now a `Monoid` whenever its output is, so encoders compose with `<>`, each field `contramap`-ped onto its encoder:

```swift
typealias Enc<A> = ByteEncoder<A, BinaryEncodeError>

let point: Enc<Point> = Enc<UInt16>.integer(.big).contramap(\.x) <> Enc<UInt16>.integer(.big).contramap(\.y)
point.run(Point(x: 1, y: 2))   // .success([0x00, 0x01, 0x00, 0x02])
```

Fallible primitives fail with `BinaryParseError` / `BinaryEncodeError`. A protocol lifts them into its own error type with `embed(_:)` through a `Prism` onto its `binary` case, and passes the same prism to the combinators that can fail on their own (`isolate`, `manyUntilEnd`, `parseAll(_:errors:)`):

```swift
let errors = MQTTDecodingError.prism.binary
let byte: ByteParser<UInt8, MQTTDecodingError> = BinaryParser<UInt8>.byte.embed(errors)
```

## Multipeer

A `MultipeerConnectivity` wrapper exposing advertiser, browser, and session events as ReactiveConcurrency `Publisher`s.

```swift
import ReactiveConcurrency
import Multipeer

let me = MCPeerID(displayName: "My Device")
let session = MultipeerSession(myselfAsPeer: me)

// Advertise — accept invitations
for await event in multipeerAdvertiserStream(myselfAsPeer: me, serviceType: "myapp").values {
    if case .success(.didReceiveInvitationFromPeer(_, _, let accept)) = event {
        accept(true, session.session)
    }
}

// Browse — invite discovered peers
for await event in multipeerBrowserStream(myselfAsPeer: me, serviceType: "myapp").values {
    if case .success(.foundPeer(let peer, _, let browser)) = event {
        _ = await session.inviteTask(peer: peer, browser: browser, context: nil, timeout: 30)
            .firstResultTask().run()
    }
}
```

`MultipeerSession` exposes `messagesStream` / `connectionsStream` as **multicast** publishers — backed by RC `PassthroughSubject`, so every subscriber receives every event — plus synchronous `send` and lazy `sendTask`:

```swift
for await msg in session.messagesStream.values {
    if case .data(let data, let peer, _) = msg { handle(data, from: peer) }
}
_ = session.send(Data("hi".utf8), to: peer)   // Result<Void, Error>
```

---

## NetworkClient

A composable, functional HTTP client built on a single requester type — `HTTPClient` — plus pure decorators for mocking, recording, and replaying traffic. Cross-platform (ReactiveConcurrency; no Combine).

### HTTPClient

`HTTPClient` is a pure function `@Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>`. Build one with a factory:

```swift
HTTPClient.live(session: .shared)                  // real network
HTTPClient.const(.ok(body: json))                  // a fixed response, built from a StubResponse
HTTPClient.const(.success((data, response)))       // a fixed Result
```

### The typed pipeline

`HTTPClient` returns the raw `(Data, HTTPURLResponse)`; decode on the response `Publisher`:

```swift
let user = HTTPClient.live(session: .shared)(request)
    .validateStatusCode()                          // 2xx -> Data, else .badStatus(code, body)
    .decode(using: JSONDecoder(), type: User.self) // Publisher<User, HTTPError>
```

### Mocking, recording & replaying (decorators)

A decorator is an `Endo<HTTPClient>` — apply it by calling it on a base client, and layer several by **nesting** (`b(a(base))`, where nesting order is execution order):

- **`override(on:use:)`** — route matching requests to another client (a `.const` mock, or a request-derived one). Develop against an endpoint that isn't built yet, or force an empty/500/timeout case.
- **`record(to:)`** — tee every real exchange to a serialized, on-disk `RecordStore` (any encoder: JSON/Plist/XML/YAML; binary IO injected via `BinaryReader`/`BinaryWriter`).
- **`playback(_:)`** — serve recorded responses from a snapshot, **consume-once** (so a polled endpoint replays `pending -> pending -> done`); unmatched requests fall through to the base — turning a flaky shared-staging e2e suite into a deterministic one.
- **`delay(_:when:clock:)`** — add artificial latency to matching responses (injected clock).

```swift
let client = HTTPClient.override(
    on: .method("GET") && .path("/currencies"),
    use: .const(.json(["MXN", "ARS", "COP", "BRL"], encoder: JSONEncoder()))
)(HTTPClient.live(session: .shared))
```

Two composable atoms drive the decorators: `RequestMatch` (`.method`/`.path`/`.query`/`.header`/`.pathRegex`, combined with `&&`/`||`/`!`) and `StubResponse` (`.ok`/`.status`/`.json`/`.failure` + `.withStatus`/`.withHeader`/`.withBody`, composed with `<>`). See the [Mocking, Recording & Replaying](https://ios.lu/NetworkTools/documentation/networkclient/mockingrecordingreplaying) guide for the full walkthrough.

## NetworkServer

An embedded HTTP server built on swift-nio (`NIOPosix`), with a **typed, functional routing DSL**. A `Router<Env>` is a value: routes compose left-to-right with Kleisli `>=>` (match -> decode body -> handle) and alternate with `<|>`. Each step is a Kleisli arrow into the `ReaderTPublisher` stack (`RouteEffect<Env, O>`), so `>=>` is its lawful bind: the first failure skips the remaining steps; `Env` is your injected environment. Handlers return `Result<Response, ResponseError>` (sync) or `Publisher<Response, ResponseError>` (async).

```swift
import NetworkServer
import ReactiveConcurrency
import ReactiveConcurrencyOperators // >=> on the ReaderTPublisher stack

struct Env: Sendable {
    let greeting: String
    let decoder: JSONDecoder   // supplied to `decodeBody(using:)` via a key path
}

struct NewUser: Decodable, Sendable { let name: String }

let router =
    when(get("/hello") >=> ignoreBody() >=> response { _, env in .html(env.greeting) },
         injecting: Env.self)
    <|> when(
        post("/users")
            >=> decodeBody(using: \.decoder)
            >=> response { (req: TypedRequest<Empty, Empty, NewUser>) in
                .json(["created": req.body.name], encoder: JSONEncoder(), status: .created)
            },
        injecting: Env.self
    )

// `startServer` returns `Reader<Env, Result<Void, Error>>`; the boundary provides the environment.
_ = startServer(host: "127.0.0.1", port: 8080, router: router)
    .provide(Env(greeting: "hi there", decoder: JSONDecoder()))
```

Routes also support **typed URL params** (`get("/users/:id", params: .decode(UserParams.self, using: \.dictionaryDecoderFactory))`) and **typed query params**, surfaced on the `TypedRequest`. Response builders on `Result<Response, ResponseError>`: `.html`, `.json(_, encoder:)`, `.raw`, `.image`. An unmatched request falls through `<|>`; a total miss is a `404`.

---

## WebSocketClient

Full-duplex WebSocket client exposing a **`WebSocketConnection`** — an ARC-managed value whose `receive`, `send`, and `ping` are ReactiveConcurrency `Publisher`s. The socket stays open while a reference is held; the last release (or `close()`) sends a normal-closure frame.

```swift
import ReactiveConcurrency
import WebSocketClient

// `webSocketConnection(with:)` returns a Publisher — nothing touches the network until subscribed.
guard case let .success(conn)? = await URLSession.shared
    .webSocketConnection(with: URL(string: "wss://echo.example.com")!)
    .firstResultTask().run() else { return }

// Send
_ = await conn.send(.text("hello")).firstResultTask().run()

// Receive — multicast via `.share()`, so multiple subscribers each get every message
for await result in conn.receive.values {
    switch result {
    case .success(.text(let text)): print("<-", text)
    case .success(.data(let bytes)): print("<- \(bytes.count) bytes")
    case .failure(let err): print("error:", err)
    }
}

// Close cleanly (also happens automatically when the last reference is released)
conn.close()
```

Custom headers (auth):

```swift
var req = URLRequest(url: URL(string: "wss://api.example.com/ws")!)
req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
guard case let .success(conn)? = await URLSession.shared.webSocketConnection(with: req).firstResultTask().run() else { return }
```

### SwiftNIO — `WebSocketClientNIO`

On Linux and Android (and on Apple platforms, if you prefer swift-nio), `WebSocketClientNIO` opens the same `WebSocketConnection` with an HTTP/1.1 upgrade over swift-nio. Fragmented messages are reassembled, pings are answered, and every client frame is masked. The random handshake and masking keys are FP `Gen` values (`WebSocketKeys`); they run against the generator in a `WebSocketNIOWorld` that the application supplies at its boundary, together with the event loop group. Plain `ws://` only.

```swift
import NIOPosix
import WebSocketClientNIO

let world = WebSocketNIOWorld(group: MultiThreadedEventLoopGroup(numberOfThreads: 1), random: SystemRandomNumberGenerator())
let conn: Publisher<WebSocketConnection, WebSocketNIOError> = WebSocketConnection
    .nio(host: "192.168.1.20", port: 9001, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 20)
    .runReader(world)
```

It is a separate product: apps that only need Apple platforms keep the URLSession factory and never link swift-nio.

### Testability

`WebSocketConnection` is a plain value built from injectable closures/publishers, so a mock is a direct construction — no protocol needed:

```swift
let mock = WebSocketConnection(
    receive: .just(.text("hi")),   // Publisher<WebSocketMessage, Error>
    send: { _ in .just(()) },
    ping: .just(()),
    cancel: {}
)
```

---

## BonjourService

Bonjour service **discovery**, **advertising**, and **resolution** — all exposed as ReactiveConcurrency `Publisher` streams. Events carry platform-agnostic value types (`BonjourServiceInfo`, `BonjourConnection`, `ResolvedServiceInfo`), not Apple-specific `NWEndpoint`s.

### Browse

```swift
import ReactiveConcurrency
import BonjourService

for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.").values {
    switch result {
    case .success(.found(let info)):           print("found:", info.name, info.txt ?? [:])
    case .success(.removed(let info)):         print("gone:", info.name)
    case .success(.updated(let old, let new)): print("updated:", old.name, "->", new.name)
    case .failure(let err):                    print("error:", err)
    }
}
```

### Advertise

```swift
for await result in bonjourListenerStream(serviceType: "_myapp._tcp.", serviceName: "My Device").values {
    switch result {
    case .success(.ready(let port)):         print("advertising on port", port ?? 0)
    case .success(.newConnection(let conn)): handleIncomingConnection(conn)   // already started
    case .success(.registered):              print("registered")
    case .failure(let err):                  print("error:", err)
    default: break
    }
}
```

With TXT record metadata, pass a `txtRecord: NWTXTRecord` (e.g. `txt["version"] = "1.0"`).

### Resolve a discovered service

```swift
// BonjourServiceInfo (from browse) -> ResolvedServiceInfo (IPs, port, TXT)
if case let .success(r)? = await bonjourResolve(info).firstResultTask().run() {
    print("host:", r.host ?? "?", "ips:", r.ips, "port:", r.port ?? 0)
}
```

### Connections

An accepted `BonjourConnection` exposes `receive` / `send` as publishers:

```swift
for await chunk in conn.receive.values {
    if case .success(let data) = chunk { handle(data) }
}
_ = await conn.send(Data("hello".utf8)).firstResultTask().run()
```

### IP address helper

```swift
let addr = IP("192.168.1.100")   // .ipv4
let v6   = IP("::1")             // .ipv6
print(addr?.ipString)            // "192.168.1.100"
print(v6?.ipUrlString)           // "[::1]"   <- brackets for URL use
let preferred = [IP("192.168.1.1")!, IP("::1")!].preferredAddress // -> .ipv6(::1)
```

---

## MQTT

MQTT 3.1.1 and 5.0 — client, broker and bridge — split by responsibility:

| Target | What it holds |
|---|---|
| `MQTT` | Role-neutral core: every packet type, every v5 property and reason code (with the per-packet property rules), a codec in both directions, topic matching, `PacketStream`, the `Transport` / `Listener` witnesses, and `ConnectionRuntime`, the effect interpreter every role shares. Pure — no sockets, no clocks. |
| `MQTTClient` | The client protocol as a pure state machine, plus its session. |
| `MQTTBroker` | The broker protocol as a pure state machine, plus its server. |
| `MQTTBridge` | Forwarding between two brokers through two client sessions. |
| `MQTTNWConnection` | `Transport` and `Listener` over Network.framework (Apple). |
| `MQTTNIO` | `Transport` and `Listener` over SwiftNIO TCP, plus a SwiftNIO MQTT-over-WebSocket `Listener` (Apple, Linux, Android). |
| `MQTTWebSocket` | `Transport` over `WebSocketClient` (binary frames, `mqtt` subprotocol). |

Every role is a pure `step: (Input) -> Stateful<State, [RuntimeCommand]>`. Time is an input (clock ticks), so keep-alive, timeouts, reconnect backoff, will delays and session expiry are pure comparisons, and everything is tested by feeding inputs and comparing commands. `ConnectionRuntime` performs the commands; open connections live in its fold, never in global state.

### Packets and codec

One MQTT 5-shaped model serves both versions; the codec decides what each version can carry and fails with a typed error rather than dropping data:

```swift
let publish = Packet.publish(Publish(
    topic: topic,
    payload: Array(#"{"id":1,"method":1001}"#.utf8),
    delivery: .atLeastOnce(identifier),
    retain: false,
    duplicate: false,
    properties: [.contentType("application/json")]
))

publish.encode(for: .v5)        // .success([0x32, …])
publish.encode(for: .v3_1_1)    // .failure(.unsupported(.properties, in: .v3_1_1))
Packet.decode(bytes, for: .v5)  // Result<Packet, MQTTDecodingError>
```

MQTT 5 property lists are checked against the rules of their packet (allowed properties, duplicates, value ranges) in both directions. `PacketStream.feed(chunk)` is a `Stateful` step that reassembles packets from whatever chunks a transport delivers.

### Client

`ClientMachine.step` covers what MQTT 3.1.1 and 5.0 require of a client: the handshake, keep-alive (pinging only when idle, honouring Server Keep Alive), QoS 0/1/2 both ways, **reconnecting with backoff**, **session resumption** (unacknowledged PUBLISH and PUBREL resent in order; subscriptions renewed when the server lost the session), the server's Receive Maximum, Maximum Packet Size, Maximum QoS and feature flags (requests it cannot accept are rejected with a typed reason), topic aliases in both directions, and protocol violations.

```swift
let options = ClientOptions(
    version: .v5,
    clientIdentifier: "ipad",
    cleanStart: true,
    keepAlive: 30,
    will: nil,
    userName: "elegoo",
    password: Array(accessCode.utf8),
    properties: [],
    maximumPacketSize: 1 << 20,
    reconnect: .exponentialBackoff(initial: .seconds(1), maximum: .seconds(30), attempts: nil)
)
let world = ClientWorld(
    transport: Transport.nwConnection(host: "192.168.1.20", port: 1883, parameters: .tcp).runReader(NWWorld(queue: queue)),
    clock: { .monotonicTicks(every: .milliseconds(250), clock: ContinuousClock()) }
)

let events: Publisher<ClientEvent, ClientError> = MQTTClient.session(options, requests: requests).runReader(world)
```

Nothing runs until `events` is subscribed; cancelling it closes the connection. Requests made while disconnected are queued.

### Broker

`BrokerMachine.step(policy)` is the server side: authentication and per-topic authorization through an injected `BrokerPolicy`, assigned client identifiers, session takeover, clean and persistent sessions with expiry, wills (with delay), QoS 0/1/2 both ways with session resumption, retained messages (Retain Handling, Retain As Published), No Local, Subscription Identifiers, shared subscriptions (round robin), overlapping subscriptions delivered once at the highest QoS, client topic aliases, Receive Maximum and Maximum Packet Size on both sides, Maximum QoS, Message Expiry, and keep-alive at 1.5×.

```swift
let clock: @Sendable () -> Publisher<Duration, Never> = { .monotonicTicks(every: .milliseconds(250), clock: ContinuousClock()) }

// Bind (an effect that reports the port), then serve on the bound listener.
let broker: Publisher<BrokerEvent, BrokerError> = Listener.nio(host: "0.0.0.0", port: 1883, tls: nil)
    .runReader(NIOWorld(group: group))
    .mapError(BrokerError.listener)
    .flatMap(maxPublishers: 1) { bound in
        MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
            .runReader(BrokerWorld(listener: bound.listener, clock: clock))
    }
```

Listeners: `Listener.nio(host:port:tls:)`, `Listener.nioWebSocket(host:port:path:maximumMessageSize:)` and `Listener.nwListener(port:parameters:)`. Each binds when subscribed and reports the port actually bound. `Listener.merge` accepts from several at once.

**Enhanced authentication (MQTT 5 AUTH).** `BrokerPolicy.challenge` is a pure function deciding each step of an exchange — accept (with data), continue (with a challenge), or refuse — for CONNECT and for re-authentication:

```swift
let policy = BrokerPolicy(
    authenticate: { _ in .success },
    mayPublish: { _, _ in true },
    maySubscribe: { _, _ in true },
    challenge: { client, method, data, round in
        switch (method, round) {
        case ("SCRAM-SHA-256", 0): .continue(data: serverFirstMessage(client, data))
        case ("SCRAM-SHA-256", 1): verify(client, data) ? .accept(data: serverFinal) : .refuse(.notAuthorized)
        default: .refuse(.badAuthenticationMethod)
        }
    }
)
```

### Bridge

`MQTTBridge.run(rules:local:remote:)` connects to two brokers (any brokers) and forwards messages by mosquitto-style rules — filter, direction, QoS, local and remote prefixes. Loops are prevented with No Local on MQTT 5 and by dropping its own echoes on 3.1.1; each side reconnects by its own `ClientOptions`.

```swift
let rule = BridgeRule(filter: printerTopics, direction: .outbound, qos: .atLeastOnce, localPrefix: "", remotePrefix: "home/")
let bridge = MQTTBridge.run(rules: [rule], local: localOptions, remote: remoteOptions)
    .runReader(BridgeWorld(local: localWorld, remote: remoteWorld))
```

### Transports and listeners

Each is built from a `Reader` over its world, so the effects (event loop group, dispatch queue, random generator) are supplied at the application's boundary:

| | Opens connections | Accepts connections | World |
|---|---|---|---|
| Network.framework | `Transport.nwConnection(host:port:parameters:)` (TLS with `.tls`) | `Listener.nwListener(port:parameters:)` | `NWWorld(queue:)` |
| SwiftNIO TCP | `Transport.nio(host:port:tls:)` | `Listener.nio(host:port:tls:)` | `NIOWorld(group:)` |
| WebSocket | `Transport.webSocket(url:session:)`, `Transport.webSocket { WebSocketConnection.nio(…).runReader(world) }` | `Listener.nioWebSocket(host:port:path:maximumMessageSize:)` | `WebSocketNIOWorld` / `NIOWorld` |
| In process | `InMemoryLink.make().transport` | `InMemoryLink.make().listener` | — |

TLS on SwiftNIO uses swift-nio-ssl's `TLSConfiguration`:

```swift
let secure = Transport.nio(host: "broker.example.com", port: 8883, tls: .makeClientConfiguration()).runReader(NIOWorld(group: group))
```

`InMemoryLink` joins a transport and a listener without a socket: run a client or a bridge in the same process as an `MQTTBroker` by merging `link.listener` into the broker's listeners.

**Redirects.** When a server answers with *Use another server* or *Server moved* and a Server Reference, the client reconnects there through `ClientWorld.redirect`, which maps the reference to a transport (`nil` declines). *Moved* is remembered for later reconnects; *use another server* applies to the next connection.

`Transport` and `Listener` are plain structs of effects, so tests use in-memory ones.

## Design principles

All three packages follow the same functional conventions via [`FP`](https://github.com/luizmb/FP):

- **`Reader`** for dependency injection (template environment, server environment, request threading). No `init` injection, no stored globals.
- **`Result`** instead of `throws` at all public API boundaries. Errors are values.
- **`Publisher`** (ReactiveConcurrency — cold, lazy, composable) for all async work, across the client, server, and streaming APIs. No Combine.
- **`FunctionWrapper`** for any `(A) -> B` that should be composable — `HTTPClient`, `Convert` / `DataDecoder` / `DataEncoder`, and `Endo` all conform.
- **Alternative (`<|>`)** for router composition — tries left then right (only 404 falls through), identity is `Router.empty`.
- **No crashing operations** — no force-unwrap, no `fatalError`, no `try!`. All failure paths return `Result` or publisher errors.
