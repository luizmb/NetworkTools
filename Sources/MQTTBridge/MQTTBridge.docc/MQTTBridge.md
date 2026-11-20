# ``MQTTBridge``

Forwards messages between two MQTT brokers.

## Overview

A bridge is an `MQTTClient` session to each broker. ``BridgeMachine`` folds both sessions'
events into requests for the other side, following ``BridgeRule``s in the spirit of Mosquitto's
`topic pattern direction qos local-prefix remote-prefix`: a message on the local broker at
`localPrefix + topic` is forwarded to `remotePrefix + topic`, and the other way round.

Loops are prevented with No Local on MQTT 5; on MQTT 3.1.1, which has no No Local, the bridge
drops the echo of messages it just forwarded. Each side reconnects, resumes and re-subscribes
according to its own `ClientOptions`.

```swift
let rule = BridgeRule(filter: printerTopics, direction: .outbound, qos: .atLeastOnce, localPrefix: "", remotePrefix: "home/")
let bridge: Publisher<BridgeEvent, BridgeError> =
    MQTTBridge.run(rules: [rule], local: localOptions, remote: remoteOptions)
        .runReader(BridgeWorld(local: localWorld, remote: remoteWorld))
```

## Topics

### Running a Bridge
- ``MQTTBridge``
- ``BridgeWorld``
- ``BridgeRule``
- ``BridgeDirection``
- ``BridgeEvent``
- ``BridgeError``

### The State Machine
- ``BridgeMachine``
- ``BridgeState``
- ``BridgeSide``
- ``BridgeOutput``
