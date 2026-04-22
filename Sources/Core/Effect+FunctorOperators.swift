import FP

// MARK: - Effect Functor Operators

// (<$>) :: (a -> b) -> Effect<i, env, a, f> -> Effect<i, env, b, f>
public func <£> <I, Env, A: Sendable, B: Sendable, F: Error>(
    _ f: @escaping @Sendable (A) -> B,
    _ e: Effect<I, Env, A, F>
) -> Effect<I, Env, B, F> {
    e.map(f)
}

// (<&>) :: Effect<i, env, a, f> -> (a -> b) -> Effect<i, env, b, f>
public func <&> <I, Env, A: Sendable, B: Sendable, F: Error>(
    _ e: Effect<I, Env, A, F>,
    _ f: @escaping @Sendable (A) -> B
) -> Effect<I, Env, B, F> {
    e.map(f)
}

// ($>) :: Effect<i, env, a, f> -> b -> Effect<i, env, b, f>
// swiftlint:disable:next identifier_name
public func £> <I, Env, A: Sendable, B: Sendable, F: Error>(
    _ e: Effect<I, Env, A, F>,
    _ value: B
) -> Effect<I, Env, B, F> {
    e.replace(with: value)
}

// (<$) :: b -> Effect<i, env, a, f> -> Effect<i, env, b, f>
public func <£ <I, Env, A: Sendable, B: Sendable, F: Error>(
    _ value: B,
    _ e: Effect<I, Env, A, F>
) -> Effect<I, Env, B, F> {
    e £> value
}
