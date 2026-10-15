import Foundation

/// Git-Branch im Arbeitsverzeichnis eines Agenten, für die Detailansicht im Dashboard
/// (status-display#52). Wird beim Öffnen der Ansicht ermittelt, nicht mit jeder Hook-Meldung.
public enum GitBranch: Equatable {
    case branch(String)
    /// Detached HEAD mit kurzem Commit.
    case detached(String)
    /// Kein Git-Repo (oder der Pfad existiert nicht mehr).
    case noRepository
    /// git fehlt, antwortet nicht oder liefert Unerwartetes – nicht als „kein Repo“ ausgeben.
    case unknown(String)

    /// Text der Zeile „Branch“: `main`, `detached 37a29d3`, `–`.
    public var text: String {
        switch self {
        case .branch(let name): return name
        case .detached(let commit): return "detached \(commit)"
        case .noRepository: return "–"
        case .unknown(let reason): return "unbekannt (\(reason))"
        }
    }

    /// Ergebnis eines git-Aufrufs: Exit-Status und stdout; nil, wenn git nicht startete oder zu
    /// lange brauchte.
    public typealias Run = (_ arguments: [String]) -> (status: Int32, output: String)?

    /// Wertet aus, was git sagt. `symbolic-ref -q` endet mit 0 und dem Branch (auch in einem
    /// frischen Repo ohne Commit), mit 1 bei detached HEAD und mit 128, wenn der Pfad kein Repo
    /// ist oder fehlt. Nur bei detached HEAD folgt ein zweiter Aufruf für den kurzen Commit.
    public static func resolve(run: Run) -> GitBranch {
        guard let head = run(["symbolic-ref", "--short", "-q", "HEAD"]) else { return .unknown(noAnswer) }
        switch head.status {
        case 0:
            let name = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? .unknown("keine Ausgabe") : .branch(name)
        case 1:
            guard let commit = run(["rev-parse", "--short", "HEAD"]) else { return .unknown(noAnswer) }
            let sha = commit.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return commit.status == 0 && !sha.isEmpty ? .detached(sha) : .unknown("HEAD nicht lesbar")
        case 128:
            return .noRepository
        default:
            return .unknown("git-Status \(head.status)")
        }
    }

    static let noAnswer = "git antwortet nicht"

    /// Menüleisten-Apps haben keinen Shell-PATH, daher feste Suchpfade (wie bei `gh`).
    public static let gitCandidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]

    /// Blockiert bis zu zwei Mal `timeout` – nie auf dem Main-Thread aufrufen.
    public static func read(path: String, candidates: [String] = gitCandidates,
                            timeout: TimeInterval = 2) -> GitBranch {
        guard let git = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .unknown("git nicht gefunden")
        }
        return resolve { arguments in
            runProcess(git, ["-C", path] + arguments, timeout: timeout)
        }
    }

    /// Startet git direkt mit Argument-Array, ohne Shell. stderr wird verworfen (eine ungelesene
    /// Pipe könnte git blockieren); stdout ist eine Zeile, weit unter dem Pipe-Puffer, und wird
    /// deshalb erst nach dem Ende gelesen.
    static func runProcess(_ executable: String, _ arguments: [String],
                           timeout: TimeInterval) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
