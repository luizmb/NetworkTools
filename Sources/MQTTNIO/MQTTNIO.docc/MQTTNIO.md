# ``MQTTNIO``

An MQTT `Transport` and `Listener`s over SwiftNIO: TCP (optionally TLS) and MQTT over WebSocket.
Apple platforms, Linux and Android.

## Overview

Everything is built from a `Reader` over ``NIOWorld`` — the event loop group, which the application
owns and supplies at its boundary:

```swift
let world = NIOWorld(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))

let plain = Transport.nio(host: "192.168.1.20", port: 1883, tls: nil).runReader(world)
let secure = Transport.nio(host: "broker.example.com", port: 8883, tls: .makeClientConfiguration()).runReader(world)

let tcp = Listener.nio(host: "0.0.0.0", port: 1883, tls: nil).runReader(world)
let webSocket = Listener.nioWebSocket(host: "0.0.0.0", port: 9001, path: "/mqtt", maximumMessageSize: 1 << 20).runReader(world)
```

Inbound bytes are buffered from the moment a channel is active, and cancelling a connection's
`receive` closes the channel. TLS uses swift-nio-ssl's `TLSConfiguration`: the client verifies the
server name (skipped for IP literals), the server presents its certificate chain and key.

## Topics

- ``NIOWorld``
