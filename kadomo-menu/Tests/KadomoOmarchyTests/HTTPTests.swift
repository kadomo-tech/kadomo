import Foundation
import Testing
@testable import KadomoOmarchy

private final class ThemeHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let headers = request.url!.path == "/declared" ? ["Content-Length": "1000000"] : [:]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        let count = request.url!.path == "/valid" ? 8 : 17
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: count))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func httpRejectsOversizedBodies() async throws {
    for path in ["valid", "declared", "unknown-length"] {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThemeHTTPProtocol.self]
        let session = URLSession(configuration: config)
        let http = OmarchyHTTP(maxBytes: 8)
        do {
            let data = try await http.get("https://theme.invalid/" + path, session: session)
            #expect(path == "valid")
            #expect(data?.count == 8)
        } catch {
            #expect(path != "valid")
            #expect(error.message.contains("larger than"))
        }
    }
}
