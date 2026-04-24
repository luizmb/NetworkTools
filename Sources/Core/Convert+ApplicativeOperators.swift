import Foundation
import FP

// MARK: - Convert Applicative Operators

// (<*>) :: Convert<i, (a -> b)> -> Convert<i, a> -> Convert<i, b>
public func <*> <Input, A, B, Failure>(
    _ f: Convert<Input, (A) -> B, Failure>,
    _ d: Convert<Input, A, Failure>
) -> Convert<Input, B, Failure> {
    Convert.apply(f, d)
}

// (*>) :: Convert<i, a> -> Convert<i, b> -> Convert<i, b>
public func *> <Input, A, B, Failure>(
    _ lhs: Convert<Input, A, Failure>,
    _ rhs: Convert<Input, B, Failure>
) -> Convert<Input, B, Failure> {
    lhs.seqRight(rhs)
}

// (<*) :: Convert<i, a> -> Convert<i, b> -> Convert<i, a>
public func <* <Input, A, B, Failure>(
    _ lhs: Convert<Input, A, Failure>,
    _ rhs: Convert<Input, B, Failure>
) -> Convert<Input, A, Failure> {
    lhs.seqLeft(rhs)
}
