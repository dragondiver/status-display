import Foundation

/// Schickt ein Ereignis synchron an die laufende App. Gibt `false` zurück, statt zu warten oder zu werfen.
public enum EventSender {
    public static func send(_ event: AgentEvent, endpoint: Endpoint, token: String, timeout: TimeInterval = 1) -> Bool {
        guard let body = try? JSONEncoder().encode(event),
              let url = URL(string: "http://127.0.0.1:\(endpoint.port)/v1/events") else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let done = DispatchSemaphore(value: 0)
        let ok = Locked(false)
        // Kein Proxy: eine PAC-Datei darf die Loopback-Anfrage samt Token nie über einen Proxy leiten.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        URLSession(configuration: configuration).dataTask(with: request) { _, response, _ in
            ok.value = (response as? HTTPURLResponse)?.statusCode == 202
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return ok.value
    }
}
