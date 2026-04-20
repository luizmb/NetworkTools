#if canImport(Combine)
@preconcurrency import Combine
import FP

extension AnyPublisher {
    func asDeferredTask() -> DeferredTask<Output> where Failure == Never {
        DeferredTask {
            await self.values.first(where: { _ in true })!
        }
    }
}
#endif
