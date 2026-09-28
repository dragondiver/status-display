import XCTest
@testable import StatusCore

final class RepoCatalogAPITests: XCTestCase {
    func testRequestBodyOmitsCursorVariableWhenNil() throws {
        let body = try JSONSerialization.jsonObject(with: RepoCatalogAPI.requestBody(cursor: nil)) as? [String: Any]
        XCTAssertEqual((body?["variables"] as? [String: Any])?.isEmpty, true)
        XCTAssertTrue((body?["query"] as? String)?.contains("$cursor") == true)
    }

    func testRequestBodyIncludesCursor() throws {
        let body = try JSONSerialization.jsonObject(with: RepoCatalogAPI.requestBody(cursor: "abc")) as? [String: Any]
        XCTAssertEqual((body?["variables"] as? [String: String])?["cursor"], "abc")
    }

    func testParseSkipsArchivedAndMalformedNodes() throws {
        let json = #"""
        {"data":{"viewer":{"repositories":{
          "nodes":[
            {"nameWithOwner":"a/b","isArchived":false},
            {"nameWithOwner":"a/old","isArchived":true},
            {"isArchived":false},
            null
          ],
          "pageInfo":{"hasNextPage":true,"endCursor":"c1"}
        }}}}
        """#
        let page = try RepoCatalogAPI.parse(Data(json.utf8))
        XCTAssertEqual(page.repos, ["a/b"])
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "c1")
    }

    func testParseLastPageHasNoCursor() throws {
        let json = #"""
        {"data":{"viewer":{"repositories":{
          "nodes":[{"nameWithOwner":"a/b","isArchived":false}],
          "pageInfo":{"hasNextPage":false,"endCursor":null}
        }}}}
        """#
        let page = try RepoCatalogAPI.parse(Data(json.utf8))
        XCTAssertFalse(page.hasNextPage)
        XCTAssertNil(page.endCursor)
    }

    func testParseGraphQLErrorWithoutData() {
        let json = #"{"data":null,"errors":[{"message":"Bad credentials"}]}"#
        XCTAssertThrowsError(try RepoCatalogAPI.parse(Data(json.utf8))) {
            XCTAssertEqual($0 as? GitHubError, .graphql("Bad credentials"))
        }
    }

    func testParseUnparsableResponseThrowsDecoding() {
        XCTAssertThrowsError(try RepoCatalogAPI.parse(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? GitHubError, .decoding)
        }
    }
}

final class RepoCatalogServiceTests: XCTestCase {
    private static func readAll(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    private func page(_ repos: [String], hasNextPage: Bool, endCursor: String?) -> Data {
        let nodes = repos.map { ["nameWithOwner": $0, "isArchived": false] }
        var pageInfo: [String: Any] = ["hasNextPage": hasNextPage]
        pageInfo["endCursor"] = endCursor as Any
        let body: [String: Any] = ["data": ["viewer": ["repositories": ["nodes": nodes, "pageInfo": pageInfo]]]]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    /// Über drei Seiten hinweg wird der `cursor` aus `endCursor` der Vorseite weitergereicht und
    /// die Repos aller Seiten landen zusammengeführt im Ergebnis.
    func testFetchFollowsPagesAndMergesResults() async throws {
        var seenCursors: [String?] = []
        var call = 0
        StubProtocol.handler = { req in
            call += 1
            // URLSession moves httpBody into httpBodyStream by the time URLProtocol sees the
            // request, so httpBody itself is nil here even though it was set on the URLRequest.
            let bodyData = req.httpBody ?? Self.readAll(req.httpBodyStream)
            let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            let variables = body?["variables"] as? [String: Any]
            seenCursors.append(variables?["cursor"] as? String)
            switch call {
            case 1: return (200, self.page(["a/one", "a/two"], hasNextPage: true, endCursor: "c1"))
            case 2: return (200, self.page(["a/three"], hasNextPage: true, endCursor: "c2"))
            default: return (200, self.page(["a/four"], hasNextPage: false, endCursor: nil))
            }
        }
        let repos = try await RepoCatalogService(tokens: FixedTokens(result: .success("tok")), session: session())
            .fetch(host: "github.com")
        XCTAssertEqual(repos, ["a/one", "a/two", "a/three", "a/four"])
        XCTAssertEqual(seenCursors, [nil, "c1", "c2"])
    }

    /// Ein Server, der `hasNextPage` nie auf `false` setzt, darf den Aufruf nicht endlos hängen
    /// lassen: nach `maxPages` Seiten bricht `fetch` ab.
    func testFetchStopsAtMaxPages() async throws {
        var call = 0
        StubProtocol.handler = { _ in
            call += 1
            return (200, self.page(["a/repo\(call)"], hasNextPage: true, endCursor: "c\(call)"))
        }
        let repos = try await RepoCatalogService(tokens: FixedTokens(result: .success("tok")), session: session())
            .fetch(host: "github.com")
        XCTAssertEqual(call, RepoCatalogService.maxPages)
        XCTAssertEqual(repos.count, RepoCatalogService.maxPages)
    }

    func testHTTPErrorAbortsFetch() async {
        StubProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await RepoCatalogService(tokens: FixedTokens(result: .success("t")), session: session())
                .fetch(host: "github.com")
            XCTFail()
        } catch { XCTAssertEqual(error as? GitHubError, .http(401)) }
    }
}
