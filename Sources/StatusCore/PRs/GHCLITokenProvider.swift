import Foundation

public protocol TokenProviding {
    func token(for host: String) throws -> String
}

/// Sammelt Bytes aus einem readabilityHandler thread-sicher ein.
private final class OutputBuffer: @unchecked Sendable {
    private var storage = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Holt das Token von `gh`. Menüleisten-Apps haben keinen Shell-PATH, daher feste Suchpfade.
public struct GHCLITokenProvider: TokenProviding {
    public let candidates: [String]
    public let timeout: TimeInterval

    public init(customPath: String? = nil, timeout: TimeInterval = 10) {
        let custom = [customPath].compactMap { $0 }.filter { !$0.isEmpty }
        self.init(candidates: custom + ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"], timeout: timeout)
    }

    public init(candidates: [String], timeout: TimeInterval = 10) {
        self.candidates = candidates
        self.timeout = timeout
    }

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
        // stderr wird verworfen statt in eine Pipe geschrieben: eine ungelesene Pipe blockiert
        // gh, sobald der Kernel-Puffer (>64 KB) voll ist, und lässt waitUntilExit() ewig hängen.
        process.standardError = FileHandle.nullDevice

        let buffer = OutputBuffer()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(chunk)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        try process.run()
        let result = semaphore.wait(timeout: .now() + timeout)
        out.fileHandleForReading.readabilityHandler = nil

        if result == .timedOut {
            process.terminate()
            throw GitHubError.ghTimeout
        }

        let token = String(decoding: buffer.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !token.isEmpty else { throw GitHubError.notLoggedIn(host) }
        return token
    }
}
