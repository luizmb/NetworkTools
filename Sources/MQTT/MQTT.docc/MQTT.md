# ``MQTT``

The MQTT protocol as pure values: every packet of MQTT 3.1.1 and 5.0, a codec in both
directions, and the transport witness the network layers implement.

## Overview

`MQTT` is the role-neutral core of the MQTT products. It has no sockets, no clocks and no
side effects — only types and pure functions:

- **One packet model for both versions.** ``Packet`` covers all fifteen control packets, shaped
  like MQTT 5 (properties, reason codes). MQTT 3.1.1 is the same model with empty properties
  and success codes.
- **A codec for every role.** ``Packet/encoder(for:)`` and ``Packet/parser(for:)`` handle every
  packet type in both directions, so a client, a broker or a bridge all use the same code.
- **No silent loss.** Encoding something the target version cannot express (properties, an
  MQTT 5-only reason code, the AUTH packet…) fails with ``MQTTEncodingError/unsupported(_:in:)``.
- **Streaming.** ``PacketStream`` turns arbitrary byte chunks into packets as a pure `Stateful` step.
- **Transport-agnostic.** ``Transport`` and ``Listener`` are protocol witnesses — structs of
  effects — implemented by `MQTTNWConnection`, `MQTTNIO` and `MQTTWebSocket`, or by test doubles.
- **One runtime for every role.** ``ConnectionRuntime`` interprets the commands of a pure
  connection machine (the client's, the broker's), keeping open connections in its fold.

```swift
let connect = Packet.connect(Connect(
    protocolVersion: .v5,
    clientIdentifier: "ipad",
    cleanStart: true,
    keepAlive: 30,
    will: nil,
    userName: "elegoo",
    password: Array(accessCode.utf8),
    properties: [.sessionExpiryInterval(0)]
))

connect.encode(for: .v5)                 // Result<[UInt8], MQTTEncodingError>
Packet.decode(bytes, for: .v5)           // Result<Packet, MQTTDecodingError>
```

### Built from combinators

The codec is written with `Core`'s binary combinators. Encoders are a `Monoid`: a packet encoder
is the `<>` of its field encoders, each `contramap`-ped onto the field it writes. Parsers are
FP's `StatefulTResult` monad, chained with `>>-`, `<*>`, `*>` and `<*`. Internally, the Will
message encoder reads:

```swift
// Will message: properties, then topic, then payload.
Wire.properties(version).contramap(\.properties)
    <> Wire.topicName(version).contramap(\.topic)
    <> Wire.binary.contramap(\.payload)
```

### Versions

``ProtocolVersion`` is a two-case enum whose raw value is the CONNECT protocol-level byte.
CONNECT is always encoded in its own ``Connect/protocolVersion`` and decoded in the version its
bytes announce, so a broker can read the first packet before it knows the session's version.

## Topics

### Packets
- ``Packet``
- ``PacketType``
- ``Connect``
- ``Will``
- ``ConnAck``
- ``Publish``
- ``Delivery``
- ``Acknowledgement``
- ``Subscribe``
- ``Subscription``
- ``SubscriptionOptions``
- ``RetainHandling``
- ``SubAck``
- ``Unsubscribe``
- ``UnsubAck``
- ``Disconnect``
- ``Auth``

### Vocabulary
- ``ProtocolVersion``
- ``QoS``
- ``PacketIdentifier``
- ``TopicName``
- ``TopicFilter``
- ``ReasonCode``
- ``Property``

### Encoding and Decoding
- ``MQTTEncoder``
- ``MQTTParser``
- ``MQTTEncodingError``
- ``MQTTDecodingError``
- ``UnsupportedFeature``
- ``PacketStream``
- ``PacketStreamError``

### Property Rules
- ``PropertyRules``
- ``PropertyContext``
- ``PropertyViolation``

### Transport
- ``Transport``
- ``TransportConnection``
- ``TransportError``
- ``Listener``
- ``BoundListener``

### Runtime
- ``ConnectionRuntime``
- ``ConnectionID``
- ``ConnectionInput``
- ``RuntimeCommand``
- ``RuntimeWorld``
