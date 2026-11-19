# Binary Codecs

Protocol-agnostic building blocks for binary wire formats: a parser monad and a monoidal encoder.

## Overview

Network protocols (MQTT, DNS/mDNS, PTP/IP, MIDI SysEx, …) mostly read and write the same things:
fixed-width integers in some byte order, variable-length integers, length-prefixed strings and
regions, and lists. `Core` provides those once; protocol targets build their codecs from them.

### Parsing: `ByteParser`

``ByteParser`` is FP's `StatefulTResult` over ``ByteInput`` (an `ArraySlice<UInt8>`), so it is
already a lawful Functor / Applicative / Monad with every FP operator. `Core` adds the primitives
(``Endianness``-aware integers, LEB128-style variable-length integers, UTF-8, raw bytes) and the
combinators a parser monad needs: ``ByteParsers/isolate(_:_:errors:)`` for length-delimited regions,
``ByteParsers/manyUntilEnd(_:errors:)``, ``ByteParsers/count(_:_:)``, backtracking `<|>`, and
``ByteParsers/optional(_:)``.

```swift
typealias P<A: Sendable> = BinaryParser<A>

let string: P<String> = P<UInt16>.integer(.big) >>- { P<String>.utf8(count: Int($0)) }
string.parseAll([0x00, 0x02, 0x68, 0x69])   // .success("hi")
```

Primitives that can fail produce ``BinaryParseError``; the rest work with any error type. A
protocol with its own error type lifts a parser with `embed(_:)` through a
`Prism<ProtocolError, BinaryParseError>`, and passes the same prism to the combinators that can
fail on their own (`isolate`, `manyUntilEnd`, `parseAll(_:errors:)`):

```swift
let errors = MQTTDecodingError.prism.binary
let byte: ByteParser<UInt8, MQTTDecodingError> = BinaryParser<UInt8>.byte.embed(errors)
```

### Encoding: `ByteEncoder`

``ByteEncoder`` is ``Convert`` with `[UInt8]` output. Because `[UInt8]` is a `Monoid`, so is
`Convert` (whenever its output is a monoid): `lhs <> rhs` runs both on the same input and
concatenates the bytes. A record encoder is the `<>` of its field encoders, each `contramap`-ped
onto its field. Encoders lift into a larger error type with `embed(_:)`, the same way.

```swift
typealias Enc<A> = ByteEncoder<A, BinaryEncodeError>

let point: Enc<Point> =
    Enc<UInt16>.integer(.big).contramap(\.x)
        <> Enc<UInt16>.integer(.big).contramap(\.y)
```

## Topics

### Parsing
- ``ByteParser``
- ``BinaryParser``
- ``ByteInput``
- ``ByteParsers``
- ``BinaryParseError``

### Encoding
- ``ByteEncoder``
- ``ByteEncoders``
- ``BinaryEncodeError``

### Shared
- ``Endianness``
