# ``MQTTBroker``

An MQTT 3.1.1 and 5.0 broker as a pure state machine plus a lazy server.

## Overview

``BrokerMachine/step(_:)`` takes the injected ``BrokerPolicy`` and returns the broker's
transition function: inputs (accepted connections, received bytes, closes, clock ticks,
application publications) in, `RuntimeCommand`s out. It never touches a socket or a clock, so
every behaviour is tested by feeding inputs and comparing commands.

It implements the server side of the protocol: authentication (including MQTT 5 enhanced
authentication, step by step through ``BrokerPolicy/challenge``) and per-topic authorization
through the policy, assigned client identifiers, session takeover, clean and persistent
sessions with Session Expiry, wills with Will Delay, QoS 0/1/2 in both directions with session
resumption, retained messages with Retain Handling and Retain As Published, No Local,
Subscription Identifiers, shared subscriptions (round robin), overlapping subscriptions
delivered once at the highest granted QoS, client topic aliases, Receive Maximum and Maximum
Packet Size on both sides, Maximum QoS, Message Expiry, and keep-alive at 1.5 × the client's
interval.

``MQTTBroker/serve(_:policy:publications:)`` runs it on the shared `ConnectionRuntime`:

```swift
let broker: Publisher<BrokerEvent, BrokerError> =
    MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
        .runReader(BrokerWorld(listener: bound.listener, clock: clock))
```

Subscribing starts the broker; cancelling stops it and closes every connection.

## Topics

### Running a Broker
- ``MQTTBroker``
- ``BrokerWorld``
- ``BrokerOptions``
- ``BrokerPolicy``
- ``AuthenticationStep``
- ``BrokerEvent``
- ``BrokerError``

### The State Machine
- ``BrokerMachine``
- ``BrokerState``
- ``BrokerInput``
- ``BrokerCommand``
