import FP

// MARK: - Effect Monad Operators

// (>>-) :: Effect<i, env, a, f> -> (a -> Effect<i, env, b, f>) -> Effect<i, env, b, f>
public func >>- <I: Sendable, Env: Sendable, A: Sendable, B: Sendable, F: Error>(
    _ e: Effect<I, Env, A, F>,
    _ f: @escaping @Sendable (A) -> Effect<I, Env, B, F>
) -> Effect<I, Env, B, F> {
    e.flatMap(f)
}

// (-<<) :: (a -> Effect<i, env, b, f>) -> Effect<i, env, a, f> -> Effect<i, env, b, f>
public func -<< <I: Sendable, Env: Sendable, A: Sendable, B: Sendable, F: Error>(
    _ f: @escaping @Sendable (A) -> Effect<I, Env, B, F>,
    _ e: Effect<I, Env, A, F>
) -> Effect<I, Env, B, F> {
    e.flatMap(f)
}

// Output-Kleisli (>=>) — input type fixed, output type varies:
// (x -> Effect<i, env, a, f>) -> (a -> Effect<i, env, b, f>) -> x -> Effect<i, env, b, f>
public func >=> <I: Sendable, Env: Sendable, X, A: Sendable, B: Sendable, F: Error>(
    _ f: @escaping (X) -> Effect<I, Env, A, F>,
    _ g: @escaping @Sendable (A) -> Effect<I, Env, B, F>
) -> (X) -> Effect<I, Env, B, F> {
    Effect.kleisli(f, g)
}

// Output-Kleisli (<=<) — right-to-left.
public func <=< <I: Sendable, Env: Sendable, X, A: Sendable, B: Sendable, F: Error>(
    _ g: @escaping @Sendable (A) -> Effect<I, Env, B, F>,
    _ f: @escaping (X) -> Effect<I, Env, A, F>
) -> (X) -> Effect<I, Env, B, F> {
    Effect.kleisliBack(g, f)
}

// Arrow Kleisli (>=>) — input type varies, environment fixed:
// Effect<a, env, b, f> >=> Effect<b, env, c, f> -> Effect<a, env, c, f>
public func >=> <A: Sendable, Env: Sendable, B: Sendable, C: Sendable, F: Error>(
    _ f: Effect<A, Env, B, F>,
    _ g: Effect<B, Env, C, F>
) -> Effect<A, Env, C, F> {
    .init { (a: A) in
        Reader { (env: Env) in
            f.run(a).runReader(env).flatMap { (result: Result<B, F>) in
                switch result {
                case .failure(let e): DeferredTask { .failure(e) }
                case .success(let b): g.run(b).runReader(env)
                }
            }
        }
    }
}

// Arrow Kleisli (<=<) — right-to-left.
public func <=< <A: Sendable, Env: Sendable, B: Sendable, C: Sendable, F: Error>(
    _ g: Effect<B, Env, C, F>,
    _ f: Effect<A, Env, B, F>
) -> Effect<A, Env, C, F> {
    f >=> g
}
