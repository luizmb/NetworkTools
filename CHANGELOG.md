# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- TLS for `Transport.nio` and `Listener.nio` (swift-nio-ssl `TLSConfiguration`). New dependency: swift-nio-ssl.
- `InMemoryLink` (a transport and listener joined in memory) and `Listener.merge`, so clients and bridges can run in the
  same process as an `MQTTBroker`.
- MQTT 5 enhanced authentication: `BrokerPolicy.challenge` drives AUTH exchanges at CONNECT and for re-authentication;
  the client sends AUTH replies before CONNACK.
- The client follows server redirects (*Use another server* / *Server moved* with a Server Reference) through
  `ClientWorld.redirect`.
- **Breaking:** transports and listeners are built from `Reader`s over their worlds — `NIOWorld` (event loop group) for
  `Transport.nio`, `Listener.nio` and `Listener.nioWebSocket`; `NWWorld` (dispatch queue) for `Transport.nwConnection`
  and `Listener.nwListener`.
- `MQTTClient` is complete: reconnects with exponential backoff (`ReconnectPolicy`), connect timeout, session
  resumption (unacknowledged PUBLISH/PUBREL resent in order; subscriptions renewed when the server lost the session),
  idle-only keep-alive honouring Server Keep Alive, the server's Receive Maximum / Maximum Packet Size / Maximum QoS /
  feature flags (refused requests reported as `ClientEvent.rejected`), topic aliases both ways, own Receive Maximum and
  Topic Alias Maximum. **Breaking:** `ClientWorld` takes a `clock` (monotonic ticks) instead of `keepAliveTimer`;
  `ClientMachine` now emits `RuntimeCommand`s.
- `MQTTBroker`: an MQTT 3.1.1/5 broker as a pure state machine (`BrokerMachine`) with an injected `BrokerPolicy` —
  sessions with expiry, takeover, wills with delay, QoS 0/1/2, retained messages, No Local, subscription identifiers,
  shared subscriptions, topic aliases, flow control, message expiry.
- `MQTTBridge`: forwarding between two brokers by mosquitto-style rules.
- `MQTT`: `ConnectionRuntime` (the effect interpreter shared by client, broker and bridge), `Listener` /
  `BoundListener`, `PropertyRules` (MQTT 5 property validation in the codec, both directions).
- Listeners: `Listener.nio`, `Listener.nioWebSocket` (MQTTNIO) and `Listener.nwListener` (MQTTNWConnection).
- `WebSocketClientNIO`: a swift-nio `WebSocketConnection` factory (HTTP/1.1 upgrade, fragment reassembly, automatic
  pong, masked frames; keys are FP `Gen` values run against the generator of a `WebSocketNIOWorld` supplied through `Reader`) so WebSockets and MQTT over WebSocket work on Linux and Android.
  `Transport.webSocket` accepts a WebSocket publisher with any failure type.
- Android support for every swift-nio target (`NetworkServer`, `MQTTNIO`); CI now builds and tests on an Android
  emulator, and runs the test suite on Windows too.
- `Core`: binary codec building blocks. `ByteParser` (FP's `StatefulTResult` over `ArraySlice<UInt8>`) with
  integer, variable-length integer, UTF-8, `isolate`, repetition and backtracking (`<|>`) combinators;
  `ByteEncoder` (`Convert<A, [UInt8], E>`), now a `Monoid` under `<>` thanks to a new
  `Convert: Monoid where Output: Monoid` conformance. Fallible primitives fail with
  `BinaryParseError` / `BinaryEncodeError`; `embed(_:)` lifts parsers and encoders into a protocol's
  error type through a `Prism`.
- `MQTT`: the MQTT 3.1.1 and 5.0 packet model (all fifteen packet types, every v5 property and reason code),
  a codec for every packet in both directions, topic name/filter validation and matching, `PacketStream`
  for reassembling packets from byte chunks, and the `Transport` witness. Encoding a feature the target
  version cannot express fails with a typed error instead of dropping it.
- `MQTTClient`: the client protocol as a pure state machine (`ClientMachine.step`) — handshake, keep-alive,
  QoS 0/1/2 in both directions, packet identifiers, request queueing, protocol violations — and
  `MQTTClient.session`, a `Reader<ClientWorld, Publisher<ClientEvent, ClientError>>` interpreter.
- MQTT transports, one target each: `MQTTNWConnection` (Network.framework, Apple only), `MQTTNIO`
  (SwiftNIO, Apple + Linux) and `MQTTWebSocket` (binary frames over `WebSocketClient`).

### Changed
- **Breaking:** depends on FP 3.0.0 and ReactiveConcurrency 2.0.0.
- **Breaking:** route steps are Kleisli arrows into the `ReaderTPublisher` stack (`RouteEffect<Env, O>`), so `>=>`
  is the stack's lawful bind (RC 2 has no operators on the bare `Reader<Env, Publisher>`). Code written with the
  DSL (`get(…) >=> ignoreBody() >=> response { … }`) is unchanged. `Router.handle(_:)` still returns the plain
  `Reader`; the stack form is `Router.pipeline`.
- **Breaking:** `render` and `loadTemplate` return `ReaderTResult<HTMLEnvironment, TemplateError, String>`, so
  `loadTemplate(name) >>- { render($0, ctx) }` keeps its meaning under FP 3. Leave with `.rawValue` to run it.
- `HTMLEnvironment` is `Sendable`.
- `Router` is a list of routes: `<|>` concatenates, and one publisher tries them in order instead of a chain of
  nested `catch`es. Same fall-through rule (only a 404 falls through).

### Performance
- Templates render into one buffer (`#each` was quadratic), read each fragment once per render, and scan
  `{{ }}` on UTF-8: 3–5.7× faster, allocations down from thousands to tens.
- `esc` / `escAttr` escape in one pass and return the input when there is nothing to escape: 3.8–8.8× faster.
- Routes split their path pattern once, `Request.path` is stored, and request bodies are not copied per chunk.
  Routing a request is 2.2× faster when the first route matches.

## [0.6.0] - 2026-07-05

### Added
- `WebSocketClient` and `BonjourService` products.
- Bonjour APIs: `bonjourBrowserStream(browser:)`, `bonjourResolve`, and a `ServiceDescription` bridge.

### Changed
- Migrated the async surface from ZIO to `Reader<Env, Publisher>` with `DeferredTask` / `Publisher`.
- `WebSocketConnection` and `BonjourConnection` are now classes with ARC-managed lifetimes.
- Swift 6.3 / Xcode 26.5; test suites migrated to `Reader<Env, Publisher>`.

## [0.5.0] - 2026-05-21

### Added
- `NetworkServer` — embedded swift-nio HTTP server with a typed functional routing DSL.

## [0.4.0] - 2026-05-18

### Added
- `Multipeer` and the core HTTP client/templating packages.

## [0.1.0] - 2026-04-24

- Initial release.

[Unreleased]: https://github.com/luizmb/NetworkTools/compare/v0.6.0...main
[0.6.0]: https://github.com/luizmb/NetworkTools/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/luizmb/NetworkTools/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/luizmb/NetworkTools/compare/v0.1.0...v0.4.0
[0.1.0]: https://github.com/luizmb/NetworkTools/releases/tag/v0.1.0
