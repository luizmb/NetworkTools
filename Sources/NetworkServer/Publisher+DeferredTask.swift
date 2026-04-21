#if canImport(Combine)
@preconcurrency import Combine
import FP

private final class _CancellableBox: @unchecked Sendable {
    var cancellable: AnyCancellable?
}

extension AnyPublisher {
    func asDeferredTask() -> DeferredTask<Output> where Failure == Never {
        DeferredTask {
            // swiftlint:disable:next force_unwrapping
            await self.values.first(where: { _ in true })!
        }
    }

    func asDeferredTask() -> DeferredTask<Result<Output, Failure>> where Output: Sendable, Failure: Sendable {
        DeferredTask {
            let box = _CancellableBox()
            return await withCheckedContinuation { continuation in
                box.cancellable = self.sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.resume(returning: .failure(error))
                        }
                        box.cancellable = nil
                    },
                    receiveValue: { value in
                        continuation.resume(returning: .success(value))
                        box.cancellable = nil
                    }
                )
            }
        }
    }
}
#endif
