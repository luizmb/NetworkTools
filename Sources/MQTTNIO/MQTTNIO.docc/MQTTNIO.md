# ``MQTTNIO``

An MQTT `Transport` over SwiftNIO TCP. Apple platforms and Linux.

## Overview

```swift
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let transport = Transport.nio(host: "192.168.1.20", port: 1883, group: group)
```

The event loop group is injected, so its owner decides when to shut it down. Inbound bytes are
buffered from the moment the channel is active, and cancelling the `receive` subscription closes
the channel.
