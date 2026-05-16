import CoreFP

// MARK: - Loading<Success, Failure>

/// A four-state lifecycle for any async operation:
///
/// ```
/// idle ───────────────────────────► loading(previous: nil)
///                                         │
///                         ┌───────────────┴──────────────┐
///                         ▼                              ▼
///               loaded(Success)         failed(Failure, previous: Success?)
///                         │                              │
///                         └──────── re-fetch ────────────┘
///                                         │
///                                         ▼
///                                loading(previous: Success?)
/// ```
///
/// The `previous` payload in `loading` and `failed` carries the last successful value so UIs
/// can keep showing stale data while a refresh is in flight or after an error.
///
/// ## Prisms
///
/// Access via `Loading<S, F>.prism.idle`, `.prism.loading`, `.prism.loaded`, `.prism.failed`
/// for use with SwiftRex receive assertions and FP composition. The namespace mirrors
/// what `FPMacros`' `@Prisms` macro would generate, but is written by hand here so the
/// macro is not required as a build-time dependency.
///
/// ## Example
///
/// ```swift
/// var state: Loading<[Movie], NetworkError> = .idle
///
/// state = state.startLoading()
/// // .loading(previous: nil)
///
/// state = state.applying(.success([movie1, movie2]))
/// // .loaded([movie1, movie2])
///
/// let rows = state.loadedOrPrevious ?? []
/// ```
public enum Loading<Success: Sendable, Failure: Error & Sendable>: Sendable {
    /// No fetch has been initiated yet.
    case idle
    /// A fetch is in progress. `previous` holds the last successful value, if any.
    case loading(previous: Success?)
    /// The last fetch succeeded.
    case loaded(Success)
    /// The last fetch failed. `previous` holds the last successful value, if any.
    case failed(Failure, previous: Success?)

    // MARK: - Prisms namespace

    /// Static prisms for each `Loading` case — mirrors the `@Prisms` macro output.
    ///
    /// ```swift
    /// store.receive(Loading<Movie, NetworkError>.prism.loaded) { movie, state in
    ///     state.detail = movie
    /// }
    /// ```
    public enum prism { // swiftlint:disable:this type_name
        /// Prism for `.idle`.
        public static var idle: CoreFP.Prism<Loading, Void> {
            CoreFP.prism(
                preview: { s in
                    guard case .idle = s else { return nil }
                    return ()
                },
                review: { _ in .idle }
            )
        }

        /// Prism for `.loading(previous:)` — focus is `Success?`.
        public static var loading: CoreFP.Prism<Loading, Success?> {
            CoreFP.prism(
                preview: { s in
                    guard case .loading(let prev) = s else { return nil }
                    return prev
                },
                review: { prev in .loading(previous: prev) }
            )
        }

        /// Prism for `.loaded` — focus is `Success`.
        public static var loaded: CoreFP.Prism<Loading, Success> {
            CoreFP.prism(
                preview: { s in
                    guard case .loaded(let v) = s else { return nil }
                    return v
                },
                review: { v in .loaded(v) }
            )
        }

        /// Prism for `.failed` — focus is `(Failure, previous: Success?)`.
        public static var failed: CoreFP.Prism<Loading, (Failure, Success?)> {
            CoreFP.prism(
                preview: { s in
                    guard case .failed(let err, let prev) = s else { return nil }
                    return (err, prev)
                },
                review: { t in .failed(t.0, previous: t.1) }
            )
        }
    }
}

// MARK: - Convenience properties

extension Loading {
    /// The loaded value, or the `previous` value from a `.loading` or `.failed` state.
    /// Returns `nil` when `.idle` or when previous is absent.
    public var loadedOrPrevious: Success? {
        switch self {
        case .idle:                      nil
        case .loading(let prev):         prev
        case .loaded(let value):         value
        case .failed(_, let prev):       prev
        }
    }

    /// `true` while a fetch is in progress.
    public var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    /// The failure value if in the `.failed` state; `nil` otherwise.
    public var error: Failure? {
        guard case .failed(let err, _) = self else { return nil }
        return err
    }
}

// MARK: - Transitions

extension Loading {
    /// Transitions to `.loading`, carrying the current `loadedOrPrevious` value.
    public func startLoading() -> Self {
        .loading(previous: loadedOrPrevious)
    }

    /// Applies a `Result` to transition to `.loaded` or `.failed`,
    /// preserving `loadedOrPrevious` as the previous value in the failure case.
    public func applying(_ result: Result<Success, Failure>) -> Self {
        switch result {
        case .success(let value): .loaded(value)
        case .failure(let error): .failed(error, previous: loadedOrPrevious)
        }
    }

    /// Wraps a `Result` as a fresh `Loading` with no prior context.
    public static func from(_ result: Result<Success, Failure>) -> Self {
        switch result {
        case .success(let value): .loaded(value)
        case .failure(let error): .failed(error, previous: nil)
        }
    }
}

// MARK: - Functor

extension Loading {
    /// Maps the `Success` type, preserving `previous` values in `.loading` and `.failed`.
    public func map<B: Sendable>(_ f: (Success) -> B) -> Loading<B, Failure> {
        switch self {
        case .idle:                          .idle
        case .loading(let prev):             .loading(previous: prev.map(f))
        case .loaded(let value):             .loaded(f(value))
        case let .failed(err, prev):         .failed(err, previous: prev.map(f))
        }
    }
}

// MARK: - Applicative

extension Loading {
    /// Combines two `Loading` values that share a `Failure` type into a `Loading` of the pair.
    ///
    /// Precedence — first match wins:
    /// 1. If either side is `.failed`, the result is `.failed` (carrying the first error
    ///    encountered and a pair of `loadedOrPrevious` values when both sides have one).
    /// 2. If either side is `.idle`, the result is `.idle`.
    /// 3. If either side is `.loading`, the result is `.loading`, with `previous` set to
    ///    the pair of `loadedOrPrevious` values when both sides have one.
    /// 4. Otherwise both sides are `.loaded`, and the result is `.loaded` with the pair.
    public static func zip<Left: Sendable, Right: Sendable>(
        _ left: Loading<Left, Failure>,
        _ right: Loading<Right, Failure>
    ) -> Loading<(Left, Right), Failure>
    where Success == (Left, Right) {
        switch (left, right) {
        case (.failed(let err, _), _),
             (_, .failed(let err, _)):
            .failed(err, previous: (Left, Right)?.zip(left.loadedOrPrevious, right.loadedOrPrevious))
        case (.idle, _), (_, .idle):
            .idle
        case (.loading(let l), _):
            .loading(previous: (Left, Right)?.zip(l, right.loadedOrPrevious))
        case (_, .loading(let r)):
            .loading(previous: (Left, Right)?.zip(left.loadedOrPrevious, r))
        case let (.loaded(l), .loaded(r)):
            .loaded((l, r))
        }
    }
}

// MARK: - Monad

extension Loading {
    /// Chains into a new `Loading` when the current state is `.loaded`.
    /// Passes `.idle`, `.loading`, and `.failed` through unchanged (adapted to `B`).
    public func flatMap<B: Sendable>(_ f: (Success) -> Loading<B, Failure>) -> Loading<B, Failure> {
        switch self {
        case .idle:
            .idle
        case .loading(let prev):
            .loading(previous: prev.flatMap { f($0).loadedOrPrevious })
        case .loaded(let value):
            f(value)
        case let .failed(err, prev):
            .failed(err, previous: prev.flatMap { f($0).loadedOrPrevious })
        }
    }
}

// MARK: - Catch

extension Loading {
    /// Recovers from `.failed` by mapping the error to another `Loading` value.
    /// `.idle`, `.loading`, and `.loaded` are passed through unchanged.
    public func `catch`(_ transform: (Failure) -> Loading<Success, Failure>) -> Loading<Success, Failure> {
        switch self {
        case .idle:                   .idle
        case .loading(let prev):      .loading(previous: prev)
        case .loaded(let value):      .loaded(value)
        case .failed(let err, _):     transform(err)
        }
    }
}

// MARK: - Equatable / Hashable

extension Loading: Equatable where Success: Equatable, Failure: Equatable {}
extension Loading: Hashable where Success: Hashable, Failure: Hashable & Error {}
