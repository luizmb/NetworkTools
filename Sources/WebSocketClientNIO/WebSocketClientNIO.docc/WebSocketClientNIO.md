# ``WebSocketClientNIO``

A SwiftNIO implementation of `WebSocketClient`'s `WebSocketConnection`: WebSockets on Apple
platforms, Linux and Android.

## Overview

`WebSocketClient` defines the connection (`receive`, `send`, `ping`, `close`); this target
opens one over SwiftNIO with an HTTP/1.1 upgrade handshake. Fragmented messages are reassembled,
pings are answered, and outgoing frames are masked as RFC 6455 requires.

The random values the protocol needs — the handshake key and one masking key per frame — are FP
`Gen` values (``WebSocketKeys``). They run against the generator in the ``WebSocketNIOWorld``,
which, with the event loop group, the application supplies at its boundary through `Reader`.

```swift
let world = WebSocketNIOWorld(group: group, random: SystemRandomNumberGenerator())
let socket: Publisher<WebSocketConnection, WebSocketNIOError> = WebSocketConnection
    .nio(host: "192.168.1.20", port: 9001, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 20, tls: nil)
    .runReader(world)
```

Pass a swift-nio-ssl `TLSConfiguration` as `tls` for `wss://`; `nil` means plain `ws://`.

## Topics

- ``WebSocketNIOWorld``
- ``WebSocketKeys``
- ``WebSocketNIOError``
