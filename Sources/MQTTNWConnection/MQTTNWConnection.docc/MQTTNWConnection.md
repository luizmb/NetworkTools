# ``MQTTNWConnection``

An MQTT `Transport` and `Listener` over Apple's Network.framework. Apple platforms only.

## Overview

Both are built from a `Reader` over ``NWWorld``, the dispatch queue Network.framework calls back
on, which the application supplies at its boundary:

```swift
let world = NWWorld(queue: DispatchQueue(label: "mqtt"))
let transport = Transport.nwConnection(host: "192.168.1.20", port: 1883, parameters: .tcp).runReader(world)
let listener = Listener.nwListener(port: 1883, parameters: .tcp).runReader(world)   // Publisher<BoundListener, …>
```

Each subscription to `connect` opens a new connection and emits once it is ready. A connection
that fails or would have to wait for a network path fails with `connectionFailed` instead of
hanging. Cancelling the `receive` subscription cancels the connection. Pass `.tls` parameters for
TLS. iOS apps need `NSLocalNetworkUsageDescription` to reach a broker on the LAN.

## Topics

- ``NWWorld``
