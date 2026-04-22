import FP

public extension Reader {
    static func pure(value: Output) -> Self {
        Reader { _ in value }
    }
}