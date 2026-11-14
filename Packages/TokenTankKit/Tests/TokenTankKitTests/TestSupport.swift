import Foundation
@testable import TokenTankKit

/// URLProtocol stub serving canned responses per request; suites using it must be
/// serialized because the state is static.
final class URLProtocolStub: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int, body: Data, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    static var handler: ((URLRequest) -> Stub?)?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let stub = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Self.requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.invalid")!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// HTTP client backed by `URLProtocolStub`.
func stubbedHTTPClient() -> HTTPClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return HTTPClient(session: URLSession(configuration: configuration))
}

/// Clears recorded requests and installs the stub handler.
func stubRequests(_ handler: @escaping (URLRequest) -> URLProtocolStub.Stub?) {
    URLProtocolStub.requests = []
    URLProtocolStub.handler = handler
}

/// Loads a JSON fixture from the test bundle.
func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

/// Builds a test account descriptor with one `apiKey` slot named `sk`.
func testAccount(
    id: UUID = UUID(),
    provider: ProviderID,
    region: Region? = nil,
    slots: [CredentialSlot] = [CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil)]
) -> AccountDescriptor {
    AccountDescriptor(
        id: id,
        provider: provider,
        region: region,
        label: "test",
        credentialSlots: slots,
        tier: nil,
        thresholds: [],
        budgets: [],
        displayCurrency: nil
    )
}
