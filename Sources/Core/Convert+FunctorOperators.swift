import Foundation
import FP

// MARK: - Convert Functor Operators

// (<$>) :: (a -> b) -> Convert<i, a> -> Convert<i, b>
public func <£> <Input, A, B, Failure>(_ f: @escaping (A) -> B, _ d: Convert<Input, A, Failure>) -> Convert<Input, B, Failure> {
    d.map(f)
}

// (<&>) :: Convert<i, a> -> (a -> b) -> Convert<i, b>
public func <&> <Input, A, B, Failure>(_ d: Convert<Input, A, Failure>, _ f: @escaping (A) -> B) -> Convert<Input, B, Failure> {
    d.map(f)
}

// ($>) :: Convert<i, a> -> b -> Convert<i, b>
// swiftlint:disable:next identifier_name
public func £> <Input, A, B, Failure>(_ d: Convert<Input, A, Failure>, _ value: B) -> Convert<Input, B, Failure> {
    d.replace(with: value)
}

// (<$) :: b -> Convert<i, a> -> Convert<i, b>
public func <£ <Input, A, B, Failure>(_ value: B, _ d: Convert<Input, A, Failure>) -> Convert<Input, B, Failure> {
    d £> value
}
