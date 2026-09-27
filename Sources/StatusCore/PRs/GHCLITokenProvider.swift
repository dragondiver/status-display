import Foundation

public protocol TokenProviding {
    func token(for host: String) throws -> String
}

/// Holt das Token von `gh`. Menüleisten-Apps haben keinen Shell-PATH, daher feste Suchpfade.
public struct GHCLITokenProvider: TokenProviding {
    public let candidates: [String]

    public init(customPath: String? = nil) {
        let custom = [customPath].compactMap { $0 }.filter { !$0.isEmpty }
        self.init(candidates: custom + ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"])
    }

    public init(candidates: [String]) { self.candidates = candidates }

    public func executable() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func token(for host: String) throws -> String {
        guard let exe = executable() else { throw GitHubError.ghNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["auth", "token", "--hostname", host]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !token.isEmpty else { throw GitHubError.notLoggedIn(host) }
        return token
    }
}
