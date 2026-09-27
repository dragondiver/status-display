import Foundation

public final class PRService {
    private let tokens: TokenProviding
    private let session: URLSession

    public init(tokens: TokenProviding, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    public func fetch(host: String, now: Date = Date()) async throws -> PRSnapshot {
        // token(for:) shells out to `gh` and can block for real time (network/prompt/hang);
        // run it off the caller's executor so a @MainActor caller (Task 11) never freezes.
        let tokens = self.tokens
        let token = try await Task.detached {
            try tokens.token(for: host)
        }.value
        var request = URLRequest(url: GitHubAPI.graphqlURL(host: host), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GitHubAPI.requestBody()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.http(0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GitHubError.http(status) }
        return try GitHubAPI.parse(data, host: host, at: now)
    }
}
