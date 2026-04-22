import FP

// MARK: - Effect Applicative Operators

// (<*>) :: Effect<i, env, (@Sendable a -> b), f> -> Effect<i, env, a, f> -> Effect<i, env, b, f>
public func <*> <I: Sendable, Env: Sendable, A: Sendable, B: Sendable, F: Error>(
    _ ff: Effect<I, Env, @Sendable (A) -> B, F>,
    _ e: Effect<I, Env, A, F>
) -> Effect<I, Env, B, F> {
    Effect.apply(ff, e)
}

// (*>) :: Effect<i, env, a, f> -> Effect<i, env, b, f> -> Effect<i, env, b, f>
public func *> <I: Sendable, Env: Sendable, A: Sendable, B: Sendable, F: Error>(
    _ lhs: Effect<I, Env, A, F>,
    _ rhs: Effect<I, Env, B, F>
) -> Effect<I, Env, B, F> {
    lhs.seqRight(rhs)
}

// (<*) :: Effect<i, env, a, f> -> Effect<i, env, b, f> -> Effect<i, env, a, f>
public func <* <I: Sendable, Env: Sendable, A: Sendable, B: Sendable, F: Error>(
    _ lhs: Effect<I, Env, A, F>,
    _ rhs: Effect<I, Env, B, F>
) -> Effect<I, Env, A, F> {
    lhs.seqLeft(rhs)
}
