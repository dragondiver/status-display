import Foundation

public struct HTTPRequest: Equatable {
    public var method: String
    public var path: String
    /// Schlüssel in Kleinbuchstaben.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method; self.path = path; self.headers = headers; self.body = body
    }
}

public struct HTTPResponse: Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    public static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Status"
        }
    }
}

public enum HTTPParser {
    public static let maxHeaderBytes = 16_384
    public static let maxBodyBytes = 1_048_576

    public enum Result: Equatable {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    public static func parse(_ data: Data) -> Result {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= maxBodyBytes else {
            return .invalid
        }
        let bodyStart = separator.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let path = String(requestLine[1]).components(separatedBy: "?")[0]
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path, headers: headers,
                                     body: Data(data[bodyStart..<bodyStart + length])))
    }
}
