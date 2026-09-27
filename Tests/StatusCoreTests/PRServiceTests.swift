import XCTest
@testable import StatusCore

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct FixedTokens: TokenProviding {
    var result: Result<String, GitHubError>
    func token(for host: String) throws -> String { try result.get() }
}

final class PRServiceTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    func testSendsBearerTokenToGHE() async throws {
        var seen: URLRequest?
        StubProtocol.handler = { req in
            seen = req
            return (200, Data(#"{"data":{"review":{"nodes":[]},"mine":{"nodes":[]}}}"#.utf8))
        }
        let s = try await PRService(tokens: FixedTokens(result: .success("tok")), session: session())
            .fetch(host: "ghe.firma.de")
        XCTAssertEqual(seen?.url?.absoluteString, "https://ghe.firma.de/api/graphql")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "bearer tok")
        XCTAssertEqual(s.host, "ghe.firma.de")
    }

    func testHTTPErrorAndTokenError() async {
        StubProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await PRService(tokens: FixedTokens(result: .success("t")), session: session()).fetch(host: "github.com")
            XCTFail()
        } catch { XCTAssertEqual(error as? GitHubError, .http(401)) }
        do {
            _ = try await PRService(tokens: FixedTokens(result: .failure(.notLoggedIn("h"))), session: session()).fetch(host: "h")
            XCTFail()
        } catch { XCTAssertEqual(error as? GitHubError, .notLoggedIn("h")) }
    }
}
