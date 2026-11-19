# ``MQTTClient``

An MQTT client as a pure state machine plus a lazy interpreter.

## Overview

The client protocol — handshake, keep-alive, QoS 0/1/2 in both directions, packet identifiers,
requests queued before CONNACK, protocol violations — is one pure function:

```swift
ClientMachine.step(_ input: ClientInput) -> Stateful<ClientState, [ClientOutput]>
```

It never touches a socket or a clock. Its outputs only *describe* effects (send this packet, tell
the application that, close), which makes every behaviour testable by feeding inputs.

``MQTTClient/session(_:requests:)`` turns that machine into a running session. It is a stream
transducer: the application's requests go in as a `Publisher`, the session's events come out as a
`Publisher`, and the outside world is injected through `Reader`:

```swift
let world = ClientWorld(
    transport: .nwConnection(host: "192.168.1.20", port: 1883, parameters: .tcp, queue: queue),
    keepAliveTimer: { seconds in
        Publisher<ContinuousClock.Instant, Never>
            .timer(every: .seconds(Int(seconds)), clock: clock)
            .map(ignore)
    }
)

let events: Publisher<ClientEvent, ClientError> =
    MQTTClient.session(options, requests: requests).runReader(world)
```

Nothing happens until `events` is subscribed — typically by a SwiftRex effect, which turns each
``ClientEvent`` into an action. Cancelling the subscription closes the connection. The session
finishes after a DISCONNECT and fails with a typed ``ClientError`` otherwise.

## Topics

### Running a Session
- ``MQTTClient``
- ``ClientWorld``
- ``ClientOptions``
- ``ClientRequest``
- ``OutgoingMessage``
- ``ClientEvent``
- ``ClientError``
- ``ProtocolViolation``

### The State Machine
- ``ClientMachine``
- ``ClientState``
- ``ClientInput``
- ``ClientOutput``
