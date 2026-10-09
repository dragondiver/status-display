import XCTest
@testable import StatusCore

extension XCTestCase {
    /// Startet einen `HTTPServer` auf einem vom System vergebenen Port (Port 0) und liefert den
    /// tatsächlich gebundenen Port zurück. Vermeidet Kollisionen, die zufällig gewählte Ports mit
    /// anderen Prozessen oder parallelen Testläufen haben können.
    func startServer(readTimeout: TimeInterval = 10,
                     handler: @escaping (HTTPRequest) -> HTTPResponse,
                     file: StaticString = #filePath, line: UInt = #line) throws -> (server: HTTPServer, port: UInt16) {
        let server = HTTPServer(port: 0, readTimeout: readTimeout, handler: handler)
        let ready = expectation(description: "bereit")
        server.onStateChange = { state in
            switch state {
            case .ready: ready.fulfill()
            case .failed(let message): XCTFail("Server nicht gestartet: \(message)", file: file, line: line)
            case .stopped: break
            }
        }
        try server.start()
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(server.boundPort, "Server meldet keinen Port", file: file, line: line)
        return (server, port)
    }
}
