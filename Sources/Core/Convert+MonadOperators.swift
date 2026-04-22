import Foundation
import FP

// MARK: - Convert Monad Operators

// (>>-) :: Convert<i, a> -> (a -> Convert<i, b>) -> Convert<i, b>
public func >>- <Input, A, B, Failure>(_ d: Convert<Input, A, Failure>, _ f: @escaping (A) -> Convert<Input, B, Failure>) -> Convert<Input, B, Failure> {
    d.flatMap(f)
}

// (-<<) :: (a -> Convert<i, b>) -> Convert<i, a> -> Convert<i, b>
public func -<< <Input, A, B, Failure>(_ f: @escaping (A) -> Convert<Input, B, Failure>, _ d: Convert<Input, A, Failure>) -> Convert<Input, B, Failure> {
    d.flatMap(f)
}

// (>=>) :: (x -> Convert<i, a>) -> (a -> Convert<i, b>) -> x -> Convert<i, b>
public func >=> <Input, X, A, B, Failure>(
    _ f: @escaping (X) -> Convert<Input, A, Failure>,
    _ g: @escaping (A) -> Convert<Input, B, Failure>
) -> (X) -> Convert<Input, B, Failure> {
    Convert.kleisli(f, g)
}

// (<=<) :: (a -> Convert<i, b>) -> (x -> Convert<i, a>) -> x -> Convert<i, b>
public func <=< <Input, X, A, B, Failure>(
    _ g: @escaping (A) -> Convert<Input, B, Failure>,
    _ f: @escaping (X) -> Convert<Input, A, Failure>
) -> (X) -> Convert<Input, B, Failure> {
    Convert.kleisliBack(g, f)
}
