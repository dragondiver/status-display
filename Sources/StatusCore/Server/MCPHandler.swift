import Foundation

/// MCP über Streamable HTTP, nur JSON-Antworten (kein SSE). Ein Tool: report_status.
public final class MCPHandler {
    public static let toolName = "report_status"

    static let instructions = """
    Melde deinen Arbeitszustand mit report_status: state=running, wenn du mit einer Aufgabe \
    beginnst; waiting, wenn du auf eine Antwort oder Freigabe des Menschen wartest; done, wenn \
    die Aufgabe fertig ist; error bei Abbruch; ended, wenn die Sitzung endet. name ist ein \
    kurzer Projektname.
    """

    static let toolDefinition: [String: Any] = [
        "name": toolName,
        "description": "Meldet den eigenen Arbeitszustand an das Status-Display auf dem Schreibtisch.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "state": ["type": "string", "enum": AgentEvent.states,
                          "description": "running | waiting (auf den Menschen) | done | error | ended"],
                "name": ["type": "string", "description": "kurzer Projektname"],
                "project": ["type": "string"],
                "detail": ["type": "string", "description": "eine Zeile, z. B. worauf du wartest"],
                "url": ["type": "string", "description": "Link zum PR, Issue oder zur Sitzung"],
            ],
            "required": ["state", "name"],
        ] as [String: Any],
    ]

    private let onEvent: (AgentEvent) -> Void
    private let clients = Locked<[String: String]>([:])

    public init(onEvent: @escaping (AgentEvent) -> Void) { self.onEvent = onEvent }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard request.method == "POST" else { return .json(405, ["error": "nur POST"]) }
        guard let message = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let method = message["method"] as? String else {
            return rpcError(id: NSNull(), code: -32700, "parse error")
        }
        guard let id = message["id"] else { return HTTPResponse(status: 202) } // Notification
        let params = message["params"] as? [String: Any] ?? [:]
        let session = request.headers["mcp-session-id"]

        switch method {
        case "initialize":
            let sessionID = UUID().uuidString
            let client = (params["clientInfo"] as? [String: Any])?["name"] as? String ?? "mcp"
            clients.mutate { $0[sessionID] = client }
            var response = rpcResult(id: id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "status-display", "version": "1.0"],
                "instructions": Self.instructions,
            ])
            response.headers["Mcp-Session-Id"] = sessionID
            return response
        case "ping":
            return rpcResult(id: id, [:])
        case "tools/list":
            return rpcResult(id: id, ["tools": [Self.toolDefinition]])
        case "tools/call":
            guard params["name"] as? String == Self.toolName else {
                return rpcError(id: id, code: -32602, "unbekanntes Tool")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let name = args["name"] as? String ?? ""
            let client = session.flatMap { s in clients.value[s] } ?? "mcp"
            let event = AgentEvent(source: "mcp:\(client)", session: session ?? name,
                                   state: args["state"] as? String ?? "",
                                   name: name.isEmpty ? nil : name, project: args["project"] as? String,
                                   detail: args["detail"] as? String, url: args["url"] as? String)
            do {
                try event.validate()
                onEvent(event)
                return rpcResult(id: id, ["content": [["type": "text", "text": "ok"]]])
            } catch {
                let text = (error as? AgentEventError)?.message ?? "\(error)"
                return rpcResult(id: id, ["content": [["type": "text", "text": text]], "isError": true])
            }
        default:
            return rpcError(id: id, code: -32601, "method not found: \(method)")
        }
    }

    private func rpcResult(id: Any, _ result: [String: Any]) -> HTTPResponse {
        .json(200, ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func rpcError(id: Any, code: Int, _ message: String) -> HTTPResponse {
        .json(200, ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }
}
