# ``MQTTWebSocket``

MQTT over WebSocket: an MQTT `Transport` built on `WebSocketClient`.

## Overview

MQTT over WebSocket sends MQTT bytes in binary frames and negotiates the `mqtt` subprotocol.
A frame may carry part of a packet or several packets — the session's `PacketStream`
reassembles them — and text frames fail with `TransportError/unexpectedData(_:)`.

```swift
let transport = Transport.webSocket(url: URL(string: "ws://10.0.1.49:9001/mqtt")!, session: session)

// or with any WebSocketClient implementation:
let custom = Transport.webSocket { openMyWebSocket() }
```
