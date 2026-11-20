# ``MQTTClient``

An MQTT client as a pure state machine plus a lazy interpreter.

## Overview

The client protocol is one pure function:

```swift
ClientMachine.step(_ input: ClientInput) -> Stateful<ClientState, [ClientCommand]>
```

It never touches a socket or a clock: time arrives as clock ticks, so keep-alive, the connect
timeout and reconnect backoff are pure comparisons, and every behaviour is tested by feeding
inputs and comparing commands. It covers what MQTT 3.1.1 and 5.0 require of a client: the
handshake, keep-alive (pinging only when idle, honouring Server Keep Alive), QoS 0/1/2 in both
directions, reconnecting with a ``ReconnectPolicy``, session resumption (unacknowledged PUBLISH
and PUBREL resent in order; subscriptions renewed when the server lost the session), the
server's ``ServerLimits`` (requests it cannot accept are reported as
``ClientEvent/rejected(_:_:)``), topic aliases in both directions, and protocol violations.

``MQTTClient/session(_:requests:)`` runs it on the shared `ConnectionRuntime`: requests in,
events out, the world injected through `Reader`:

```swift
let world = ClientWorld(
    transport: Transport.nwConnection(host: "192.168.1.20", port: 1883, parameters: .tcp).runReader(NWWorld(queue: queue)),
    clock: { .monotonicTicks(every: .milliseconds(250), clock: ContinuousClock()) }
)

let events: Publisher<ClientEvent, ClientError> =
    MQTTClient.session(options, requests: requests).runReader(world)
```

Nothing happens until `events` is subscribed — typically by a SwiftRex effect, which turns each
``ClientEvent`` into an action. Cancelling the subscription closes the connection.

## Topics

### Running a Session
- ``MQTTClient``
- ``ClientWorld``
- ``ClientOptions``
- ``ReconnectPolicy``
- ``ClientRequest``
- ``RequestRejection``
- ``OutgoingMessage``
- ``ClientEvent``
- ``ClientError``
- ``ProtocolViolation``

### The State Machine
- ``ClientMachine``
- ``ClientState``
- ``ClientInput``
- ``ClientCommand``
- ``ServerLimits``
