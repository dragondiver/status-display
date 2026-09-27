import XCTest
@testable import StatusCore

final class HTTPParserTests: XCTestCase {
    private func raw(_ s: String) -> Data { Data(s.utf8) }

    func testCompleteRequest() {
        let r = HTTPParser.parse(raw("POST /v1/events?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 2\r\nAuthorization: Bearer t\r\n\r\n{}"))
        guard case .complete(let req) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/v1/events")
        XCTAssertEqual(req.headers["authorization"], "Bearer t")
        XCTAssertEqual(req.body, raw("{}"))
    }

    func testIncompleteHeaderAndBody() {
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Le")), .incomplete)
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n{}")), .incomplete)
    }

    func testInvalid() {
        XCTAssertEqual(HTTPParser.parse(raw("GARBAGE\r\n\r\n")), .invalid)
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")), .invalid)
        XCTAssertEqual(HTTPParser.parse(Data(repeating: 65, count: 20_000)), .invalid)
    }

    func testResponseSerialization() {
        let s = String(decoding: HTTPResponse.json(202, ["ok": true]).serialized(), as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        XCTAssertTrue(s.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(s.contains("Connection: close\r\n"))
        XCTAssertTrue(s.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }
}
