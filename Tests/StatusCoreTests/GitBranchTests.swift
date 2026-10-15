import XCTest
@testable import StatusCore

final class GitBranchTests: XCTestCase {
    // MARK: Auswertung der git-Ausgabe

    /// Gibt je Aufruf die vorgegebene Antwort zurück und merkt sich die Argumente.
    private func fakeGit(_ answers: [[String]: (status: Int32, output: String)?]) -> (GitBranch.Run, () -> [[String]]) {
        var calls: [[String]] = []
        let run: GitBranch.Run = { args in
            calls.append(args)
            return answers[args] ?? nil
        }
        return (run, { calls })
    }

    private let head = ["symbolic-ref", "--short", "-q", "HEAD"]
    private let commit = ["rev-parse", "--short", "HEAD"]

    func testBranch() {
        let (run, calls) = fakeGit([head: (0, "feature/beispiel\n")])
        XCTAssertEqual(GitBranch.resolve(run: run), .branch("feature/beispiel"))
        XCTAssertEqual(calls(), [head], "kein zweiter Aufruf, wenn HEAD auf einen Branch zeigt")
    }

    func testDetachedHeadShowsShortCommit() {
        let (run, calls) = fakeGit([head: (1, ""), commit: (0, "37a29d3\n")])
        XCTAssertEqual(GitBranch.resolve(run: run), .detached("37a29d3"))
        XCTAssertEqual(calls(), [head, commit])
    }

    func testNoRepository() {
        let (run, calls) = fakeGit([head: (128, "")])
        XCTAssertEqual(GitBranch.resolve(run: run), .noRepository)
        XCTAssertEqual(calls(), [head])
    }

    func testGitWithoutAnswerIsUnknownNotNoRepository() {
        XCTAssertEqual(GitBranch.resolve(run: fakeGit([:]).0), .unknown("git antwortet nicht"))
        XCTAssertEqual(GitBranch.resolve(run: fakeGit([head: (1, "")]).0), .unknown("git antwortet nicht"))
        XCTAssertEqual(GitBranch.resolve(run: fakeGit([head: (1, ""), commit: (128, "")]).0),
                       .unknown("HEAD nicht lesbar"))
        XCTAssertEqual(GitBranch.resolve(run: fakeGit([head: (0, "\n")]).0), .unknown("keine Ausgabe"))
        XCTAssertEqual(GitBranch.resolve(run: fakeGit([head: (2, "")]).0), .unknown("git-Status 2"))
    }

    func testText() {
        XCTAssertEqual(GitBranch.branch("main").text, "main")
        XCTAssertEqual(GitBranch.detached("37a29d3").text, "detached 37a29d3")
        XCTAssertEqual(GitBranch.noRepository.text, "–")
        XCTAssertEqual(GitBranch.unknown("git nicht gefunden").text, "unbekannt (git nicht gefunden)")
    }

    // MARK: Echtes git

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gitbranch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func git(_ dir: URL, _ args: String...) throws -> String {
        let exe = try XCTUnwrap(GitBranch.gitCandidates.first { FileManager.default.isExecutableFile(atPath: $0) })
        let result = try XCTUnwrap(GitBranch.runProcess(exe, ["-C", dir.path] + args, timeout: 10))
        XCTAssertEqual(result.status, 0, args.joined(separator: " "))
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testRealRepositoryBranchDetachedAndPlainFolder() throws {
        let repo = try tempDir()
        _ = try git(repo, "init", "-q", "-b", "beispiel-branch")
        // Frisches Repo ohne Commit: Der Branch steht trotzdem fest.
        XCTAssertEqual(GitBranch.read(path: repo.path), .branch("beispiel-branch"))

        _ = try git(repo, "-c", "user.name=Kollegin A", "-c", "user.email=kollegin-a@example.invalid",
                    "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "Beispiel")
        let sub = repo.appendingPathComponent("unterordner")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(GitBranch.read(path: sub.path), .branch("beispiel-branch"))

        _ = try git(repo, "checkout", "-q", "--detach")
        let short = try git(repo, "rev-parse", "--short", "HEAD")
        XCTAssertFalse(short.isEmpty)
        XCTAssertEqual(GitBranch.read(path: repo.path), .detached(short))

        let plain = try tempDir()
        XCTAssertEqual(GitBranch.read(path: plain.path), .noRepository)
        XCTAssertEqual(GitBranch.read(path: plain.appendingPathComponent("gibt-es-nicht").path), .noRepository)
    }

    func testMissingGit() {
        XCTAssertEqual(GitBranch.read(path: "/private/tmp", candidates: ["/nicht/vorhanden/git"]),
                       .unknown("git nicht gefunden"))
    }

    func testHangingGitTimesOut() throws {
        let dir = try tempDir()
        let script = dir.appendingPathComponent("git")
        try "#!/bin/sh\nsleep 5\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let start = Date()
        XCTAssertEqual(GitBranch.read(path: dir.path, candidates: [script.path], timeout: 0.5),
                       .unknown("git antwortet nicht"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
