import Foundation

/// Prüft Token, validiert und reicht weiter. Läuft auf der Server-Queue;
/// `onEvent`/`onStatus` müssen selbst auf den Main-Thread wechseln.
public final class IngressRouter {
    private let token: String
    private let knownPresets: Locked<Set<String>>
    private let mcp: ((HTTPRequest) -> HTTPResponse)?
    private let onEvent: (AgentEvent) -> Void
    private let onStatus: (String, TimeInterval?) -> Void

    public init(token: String, knownPresets: Locked<Set<String>>, mcp: ((HTTPRequest) -> HTTPResponse)? = nil,
                onEvent: @escaping (AgentEvent) -> Void, onStatus: @escaping (String, TimeInterval?) -> Void) {
        self.token = token; self.knownPresets = knownPresets; self.mcp = mcp
        self.onEvent = onEvent; self.onStatus = onStatus
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        if request.method == "GET" && request.path == "/v1/health" { return .json(200, ["ok": true]) }
        guard authorized(request) else { return .json(401, ["error": "Token fehlt oder falsch"]) }
        switch (request.method, request.path) {
        case ("POST", "/v1/events"):
            do {
                let event = try JSONDecoder().decode(AgentEvent.self, from: request.body)
                try event.validate()
                onEvent(event)
                return .json(202, ["ok": true])
            } catch let error as AgentEventError {
                return .json(400, ["error": error.message])
            } catch {
                return .json(400, ["error": "ungültiges JSON"])
            }
        case ("POST", "/v1/status"):
            struct Body: Decodable { let preset: String; let minutes: Double? }
            guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else {
                return .json(400, ["error": "ungültiges JSON"])
            }
            guard knownPresets.value.contains(body.preset) else {
                return .json(400, ["error": "unbekannter Status: \(body.preset)"])
            }
            onStatus(body.preset, body.minutes.map { $0 * 60 })
            return .json(202, ["ok": true])
        case (_, "/mcp"):
            guard let mcp else { return .json(404, ["error": "nicht gefunden"]) }
            return mcp(request)
        default:
            return .json(404, ["error": "nicht gefunden"])
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        return constantTimeEquals(header, "Bearer \(token)")
    }
}

func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in x.indices { diff |= x[i] ^ y[i] }
    return diff == 0
}
