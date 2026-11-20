# ``WebSocketClientNIO``

A SwiftNIO implementation of `WebSocketClient`'s `WebSocketConnection`: WebSockets on Apple
platforms, Linux and Android.

## Overview

`WebSocketClient` defines the connection (`receive`, `send`, `ping`, `close`); this target
opens one over SwiftNIO with an HTTP/1.1 upgrade handshake. Fragmented messages are reassembled,
pings are answered, and outgoing frames are masked as RFC 6455 requires. The random handshake and
masking keys come from an injected ``WebSocketRandomness`` (``WebSocketRandomness/system`` in
production, fixed values in tests).

```swift
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let socket: Publisher<WebSocketConnection, WebSocketNIOError> = WebSocketConnection.nio(
    host: "192.168.1.20",
    port: 9001,
    path: "/mqtt",
    protocols: ["mqtt"],
    maximumMessageSize: 1 << 20,
    group: group,
    randomness: .system
)
```

Plain `ws://` only; TLS (`wss://`) is not part of this target.

## Topics

- ``WebSocketRandomness``
- ``WebSocketNIOError``
