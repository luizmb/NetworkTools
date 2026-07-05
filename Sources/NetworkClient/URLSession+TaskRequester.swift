import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

public extension URLSession {
    var taskRequester: TaskRequester {
        Reader { [self] request in
            Publisher.future {
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
