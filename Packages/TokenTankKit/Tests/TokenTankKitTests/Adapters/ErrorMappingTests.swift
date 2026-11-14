import Foundation
import Testing
@testable import TokenTankKit

struct ErrorMappingTests {
    @Test func httpMatrixMapsToProviderError() {
        let body = Data(#"{"error": {"code": "data_not_ready", "message": "not ready"}}"#.utf8)
        #expect(ProviderError.fromHTTP(status: 401, body: Data(), retryAfter: nil) == .invalidKey)
        #expect(ProviderError.fromHTTP(status: 403, body: Data(), retryAfter: nil) == .invalidKey)
        #expect(ProviderError.fromHTTP(status: 429, body: Data(), retryAfter: 30) == .rateLimited(retryAfter: 30))
        #expect(ProviderError.fromHTTP(status: 429, body: Data(), retryAfter: nil) == .rateLimited(retryAfter: nil))
        #expect(ProviderError.fromHTTP(status: 400, body: body, retryAfter: nil) == .dataNotReady)
        #expect(ProviderError.fromHTTP(status: 500, body: Data(), retryAfter: nil) == .server(status: 500))
        #expect(ProviderError.fromHTTP(status: 404, body: Data(), retryAfter: nil) == .server(status: 404))
        #expect(ProviderError.fromHTTP(status: 400, body: Data("junk".utf8), retryAfter: nil) == .server(status: 400))
    }
}
