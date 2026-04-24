import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP

public extension URLSession {
    var taskRequester: TaskRequester {
        ZIO { [self] request in
            DeferredTask {
                do {
                    let (data, response) = try await self.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return .failure(.network(URLError(.badServerResponse)))
                    }
                    return .success((data, httpResponse))
                } catch {
                    return .failure(.network(error))
                }
            }
        }
    }
}
