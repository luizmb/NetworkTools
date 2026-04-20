#if canImport(Combine)
@preconcurrency import Combine
import FP

extension AnyPublisher {
    func asDeferredTask() -> DeferredTask<Output> where Failure == Never {
        DeferredTask {
            // swiftlint:disable:next force_unwrapping
            await self.values.first(where: { _ in true })!
        }
    }
}
#endif
