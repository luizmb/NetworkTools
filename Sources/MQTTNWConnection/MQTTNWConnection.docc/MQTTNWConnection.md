# ``MQTTNWConnection``

An MQTT `Transport` over Apple's Network.framework (`NWConnection`). Apple platforms only.

## Overview

```swift
let transport = Transport.nwConnection(
    host: "192.168.1.20",
    port: 1883,
    parameters: .tcp,
    queue: DispatchQueue(label: "mqtt")
)
```

Each subscription to `connect` opens a new connection and emits once it is ready. A connection
that fails or would have to wait for a network path fails with
`TransportError/connectionFailed(_:)` instead of hanging. Cancelling the `receive`
subscription cancels the connection. iOS apps need `NSLocalNetworkUsageDescription` to reach a
broker on the LAN.
