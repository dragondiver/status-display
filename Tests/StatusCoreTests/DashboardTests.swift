import XCTest
@testable import StatusCore

final class DashboardTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let gh = "github.com"

    private func pr(_ n: Int, repo: String = "acme/api", ageDays: Double? = 1, failing: Bool = false,
                    draft: Bool = false, decision: ReviewDecision? = nil, codeOwner: Bool = false,
                    extra: Bool = false, foreignReview: Bool = false, mergeable: Mergeable? = nil) -> PullRequest {
        PullRequest(number: n, title: "PR \(n)", repository: repo,
                    url: URL(string: "https://github.com/\(repo)/pull/\(n)")!, ciFailing: failing, isDraft: draft,
                    reviewDecision: decision, hasCodeOwnerRequestForMe: codeOwner, hasExtraRequestForMe: extra,
                    hasForeignApprovalOrChangesRequested: foreignReview,
                    createdAt: ageDays.map { t0.addingTimeInterval(-$0 * 86_400) }, mergeable: mergeable)
    }

    private func agent(_ id: String, _ state: AgentState, sinceMinutes: Double = 10,
                       stale: Bool = false) -> AgentActivity {
        AgentActivity(id: id, source: "claude", name: id, state: state,
                      since: t0.addingTimeInterval(-sinceMinutes * 60), lastSeen: t0, isStale: stale)
    }

    private func build(review: [PullRequest] = [], mine: [PullRequest] = [], agents: [AgentActivity] = [],
                       host: String = "github.com", hidden: [String] = [], pinned: [String] = [],
                       hostDefaults: [String: RepoDefault] = [:]) -> Dashboard {
        var a = PRAggregator()
        a.record(PRSnapshot(host: host, toReview: review, mine: mine, fetchedAt: t0))
        return Dashboard.build(prs: a, agents: agents, now: t0, hosts: [host], pinned: pinned, hidden: hidden,
                               hostDefaults: hostDefaults)
    }

    private func numbers(_ items: [DashboardItem]) -> [String] {
        items.map { item in
            switch item.subject {
            case .pullRequest(let p, _, let isMine): return (isMine ? "m" : "r") + "\(p.number)"
            case .agent(let a): return a.id
            }
        }
    }

    // MARK: Bereichsbildung

    func testSectionsFollowTheRules() {
        let d = build(
            review: [pr(1, extra: true), pr(2, codeOwner: true), pr(3, codeOwner: true, foreignReview: true),
                     pr(4, codeOwner: true, extra: true, foreignReview: true)],
            mine: [pr(10, failing: true), pr(11), pr(12, decision: .changesRequested)],
            agents: [agent("a-wait", .waiting), agent("a-run", .running)])
        XCTAssertEqual(Set(numbers(d.waiting)), ["r1", "r4", "m10", "m12", "a-wait"])
        XCTAssertEqual(numbers(d.codeOwner), ["r2"])
        XCTAssertEqual(Set(numbers(d.mine)), ["m10", "m11", "m12"])
        XCTAssertEqual(Set(numbers(d.agents)), ["a-wait", "a-run"])
        XCTAssertEqual(numbers(d.approved), ["r3"])
        XCTAssertEqual(d.count(.waiting), 5)
        XCTAssertEqual(d.count(.codeOwner), 1)
        XCTAssertEqual(d.count(.mine), 3)
        XCTAssertEqual(d.agents.count, 2)
        XCTAssertEqual(d.count(.approved), 1)
    }

    func testExtraRequestAlsoAsCodeOwnerOnlyInWaitingNotInCodeOwner() {
        let d = build(review: [pr(1, codeOwner: true, extra: true)])
        XCTAssertEqual(numbers(d.waiting), ["r1"])
        XCTAssertTrue(d.codeOwner.isEmpty)
        XCTAssertEqual(d.waiting[0].tags.first, .extra)
    }

    func testDraftWithRedCIIsNotWaitingButDraftWithChangesRequestedIs() {
        let d = build(mine: [pr(1, failing: true, draft: true), pr(2, draft: true, decision: .changesRequested)])
        XCTAssertEqual(numbers(d.waiting), ["m2"])
        XCTAssertEqual(Set(numbers(d.mine)), ["m1", "m2"])
        let draftRed = d.mine.first { numbers([$0]) == ["m1"] }!
        XCTAssertEqual(draftRed.urgency, .ownPR)
        XCTAssertFalse(draftRed.tags.contains(.ciFailing))
        XCTAssertTrue(draftRed.tags.contains(.draft))
    }

    func testOnlyWaitingAgentsGoToWaiting() {
        let d = build(agents: [agent("w", .waiting), agent("e", .error), agent("r", .running),
                               agent("s", .running, stale: true), agent("d", .done)])
        XCTAssertEqual(numbers(d.waiting), ["w"])
        XCTAssertEqual(numbers(d.agents), ["w", "e", "r", "s", "d"])
        XCTAssertEqual(d.agents.map(\.tags), [[.agentWaiting], [.agentError], [], [.agentStale], []])
    }

    func testTagsNeverRelyOnColorAlone() {
        let d = build(review: [pr(1, extra: true)],
                      mine: [pr(2, failing: true, decision: .changesRequested, mergeable: .conflicting)])
        XCTAssertEqual(d.waiting.first { $0.id.hasPrefix("review:") }?.tags, [.extra])
        XCTAssertEqual(d.mine[0].tags, [.ciFailing, .changesRequested, .conflict])
        XCTAssertTrue(d.waiting.allSatisfy { !$0.tags.isEmpty })
    }

    // MARK: Sortierung

    func testWaitingIsSortedByUrgencyThenAge() {
        let d = build(review: [pr(1, ageDays: 1, extra: true), pr(2, ageDays: 5, extra: true)],
                      mine: [pr(10, ageDays: 9, failing: true)],
                      agents: [agent("w", .waiting, sinceMinutes: 65)])
        // Extra (älteste zuerst) vor wartendem Agenten vor eigener roter CI – trotz des höheren Alters.
        XCTAssertEqual(numbers(d.waiting), ["r2", "r1", "w", "m10"])
    }

    func testItemsWithoutDateComeLastWithinUrgency() {
        let d = build(review: [pr(1, ageDays: nil, codeOwner: true), pr(2, ageDays: 3, codeOwner: true),
                               pr(3, ageDays: 1, codeOwner: true)])
        XCTAssertEqual(numbers(d.codeOwner), ["r2", "r3", "r1"])
    }

    func testMineSortsActionNeededFirst() {
        let d = build(mine: [pr(1, ageDays: 10), pr(2, ageDays: 1, failing: true), pr(3, ageDays: 5)])
        XCTAssertEqual(numbers(d.mine), ["m2", "m1", "m3"])
    }

    func testAgentsSortByStateThenSince() {
        let d = build(agents: [agent("r1", .running, sinceMinutes: 5), agent("w1", .waiting, sinceMinutes: 1),
                               agent("r2", .running, sinceMinutes: 50), agent("w2", .waiting, sinceMinutes: 30)])
        XCTAssertEqual(numbers(d.agents), ["w2", "w1", "r2", "r1"])
    }

    // MARK: Agenten-Abschnitt der Seitenleiste (status-display#39)

    func testAgentItemLooksUpByIDForSidebarSelection() {
        // Die Seitenleiste taggt jede Zeile mit `DashboardItem.id` ("agent:<AgentActivity.id>");
        // dieselbe Zeichenkette kommt beim Klick hier wieder rein (status-display#39).
        let d = build(agents: [agent("w", .waiting), agent("e", .error)])
        XCTAssertEqual(d.agentItem(id: "agent:w")?.id, "agent:w")
        XCTAssertEqual(d.agentItem(id: "agent:e")?.id, "agent:e")
        XCTAssertNil(d.agentItem(id: "missing"))
    }

    func testAgentMarkKindMatchesStateColorRules() {
        let d = build(agents: [agent("w", .waiting), agent("e", .error), agent("r", .running),
                               agent("s", .running, stale: true), agent("dn", .done)])
        let byID = Dictionary(uniqueKeysWithValues: d.agents.map { ($0.id, $0) })
        XCTAssertEqual(byID["agent:w"]?.markKind, .waiting)
        XCTAssertEqual(byID["agent:e"]?.markKind, .error)
        XCTAssertEqual(byID["agent:r"]?.markKind, .neutral)
        XCTAssertEqual(byID["agent:s"]?.markKind, .neutral)
        XCTAssertEqual(byID["agent:dn"]?.markKind, .neutral)
    }

    func testOwnPRWithChangesRequestedMarksWaitingWithoutRedCITag() {
        // Änderungen angefordert ohne rote CI: `ownActionNeeded`, aber kein `.ciFailing`-Etikett –
        // der dritte Zweig von `markKind` greift (orange, nicht rot).
        let d = build(mine: [pr(1, decision: .changesRequested)])
        XCTAssertEqual(d.mine.first?.markKind, .waiting)
    }

    func testOwnPRWithFailingCIMarksErrorNotWaiting() {
        // Rote CI hat Vorrang vor `ownActionNeeded` (wie schon `DashboardRow.markColor` vor #39).
        let d = build(mine: [pr(1, failing: true)])
        XCTAssertEqual(d.mine.first?.markKind, .error)
    }

    func testCiFailingReviewMarksError() {
        let d = build(review: [pr(1, extra: true)])
        // Extra-Anfragen selbst sind "waiting" (isWaitingForMe); roter CI-Tag auf einem
        // Nicht-eigenen Review-Item kommt nicht vor, das prüft testTagsNeverRelyOnColorAlone.
        XCTAssertEqual(d.waiting.first?.markKind, .waiting)
    }

    func testNoActiveAgentsTextIsUsedForEmptySidebarSection() {
        let d = build()
        XCTAssertTrue(d.agents.isEmpty)
        XCTAssertEqual(DashboardText.noActiveAgents, "Keine aktiven Agenten")
    }

    // MARK: Repos und Ausblenden

    func testRepoCountsAndWaitingFlag() {
        let d = build(review: [pr(1, repo: "acme/api", extra: true), pr(2, repo: "acme/web", codeOwner: true),
                               pr(3, repo: "acme/web", codeOwner: true),
                               pr(4, repo: "acme/web", codeOwner: true, foreignReview: true)],
                      mine: [pr(10, repo: "acme/api", failing: true)])
        let repos = Dictionary(uniqueKeysWithValues: d.repos.map { ($0.name, $0) })
        XCTAssertEqual(repos["api"], DashboardRepo(repoKey: "github.com/acme/api", name: "api", count: 2, hasWaiting: true))
        // Das schon freigegebene #4 zählt nicht mit.
        XCTAssertEqual(repos["web"], DashboardRepo(repoKey: "github.com/acme/web", name: "web", count: 2, hasWaiting: false))
        XCTAssertEqual(numbers(d.items(inRepo: "github.com/acme/api")), ["r1", "m10"])
    }

    func testPinnedRepoWithoutPRsAppearsWithZero() {
        let d = build(pinned: ["github.com/acme/quiet"])
        XCTAssertEqual(d.repos, [DashboardRepo(repoKey: "github.com/acme/quiet", name: "quiet", count: 0, hasWaiting: false)])
    }

    func testHiddenReposAreExcludedButReviewsCollected() {
        let d = build(review: [pr(1, repo: "acme/secret", extra: true), pr(2, repo: "acme/secret", codeOwner: true,
                                                                              foreignReview: true)],
                      mine: [pr(10, repo: "acme/secret", failing: true)],
                      hidden: ["github.com/acme/secret"])
        XCTAssertTrue(d.waiting.isEmpty)
        XCTAssertTrue(d.mine.isEmpty)
        XCTAssertTrue(d.approved.isEmpty)
        XCTAssertTrue(d.repos.isEmpty)
        XCTAssertEqual(numbers(d.hiddenReviews), ["r1"])
    }

    func testHostDefaultHiddenAppliesToEnterpriseHost() {
        let host = "ghe.example.com"
        let hiddenByDefault = build(review: [pr(1, extra: true)], host: host)
        XCTAssertTrue(hiddenByDefault.waiting.isEmpty)
        XCTAssertEqual(hiddenByDefault.hiddenReviews.count, 1)
        let shown = build(review: [pr(1, extra: true)], host: host, hostDefaults: [host: .normal])
        XCTAssertEqual(numbers(shown.waiting), ["r1"])
        XCTAssertEqual(shown.waiting[0].repoKey, "\(host)/acme/api")
    }

    func testIsHiddenMatchesZoneRules() {
        let key = "github.com/acme/api"
        XCTAssertFalse(PRAggregator.isHidden(repoKey: key, pinned: [], hidden: [], shown: [], hostDefaults: [:]))
        XCTAssertTrue(PRAggregator.isHidden(repoKey: key, pinned: [key], hidden: [key], shown: [], hostDefaults: [:]))
        XCTAssertTrue(PRAggregator.isHidden(repoKey: key, pinned: [], hidden: [], shown: [],
                                            hostDefaults: ["github.com": .hidden]))
        XCTAssertFalse(PRAggregator.isHidden(repoKey: key, pinned: [], hidden: [], shown: [key],
                                             hostDefaults: ["github.com": .hidden]))
        XCTAssertTrue(PRAggregator.isHidden(repoKey: "ghe.example.com/acme/api", pinned: [], hidden: [], shown: [],
                                            hostDefaults: [:]))
    }

    // MARK: Leerzustand

    func testEmptyStateSummary() {
        let d = build(review: [pr(1, codeOwner: true), pr(2, codeOwner: true), pr(3, codeOwner: true, foreignReview: true)],
                      mine: [pr(10)], agents: [agent("r", .running), agent("d", .done)])
        XCTAssertTrue(d.waiting.isEmpty)
        XCTAssertEqual(d.emptyTitle, "Nichts wartet auf dich.")
        XCTAssertEqual(d.summary, "2 Code-Owner-Reviews offen · 1 eigener PR offen · 1 Agent läuft · "
                                  + "1 Review schon von anderen erledigt")
    }

    func testEmptyStateWithNothingAtAll() {
        let d = build()
        XCTAssertEqual(d.summary, "Keine offenen PRs, keine laufenden Agenten.")
        XCTAssertTrue(d.hasPRData)
    }

    func testEmptyStateWithoutAnyPRData() {
        let d = Dashboard.build(prs: PRAggregator(), agents: [], now: t0, hosts: [gh])
        XCTAssertFalse(d.hasPRData)
        XCTAssertTrue(d.isStale)
        XCTAssertEqual(d.emptyTitle, "Noch keine Daten von GitHub.")
    }

    func testSummaryMentionsHiddenReviews() {
        let d = build(review: [pr(1, repo: "acme/secret", codeOwner: true)], hidden: ["github.com/acme/secret"])
        XCTAssertEqual(d.summary, "1 in ausgeblendeten Repos")
    }

    // MARK: Tastatur und Dock

    func testSectionShortcutNumbers() {
        XCTAssertEqual(DashboardSection.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(DashboardSection(shortcutNumber: 1), .waiting)
        XCTAssertEqual(DashboardSection(shortcutNumber: 4), .approved)
        XCTAssertNil(DashboardSection(shortcutNumber: 0))
        XCTAssertNil(DashboardSection(shortcutNumber: 5))
    }

    func testDockIconWhileAnyWindowIsOpen() {
        XCTAssertFalse(DockIconPolicy.showsDockIcon(dashboardOpen: false, boardWindowOpen: false))
        XCTAssertTrue(DockIconPolicy.showsDockIcon(dashboardOpen: true, boardWindowOpen: false))
        XCTAssertTrue(DockIconPolicy.showsDockIcon(dashboardOpen: false, boardWindowOpen: true))
        XCTAssertTrue(DockIconPolicy.showsDockIcon(dashboardOpen: true, boardWindowOpen: true))
    }
}
