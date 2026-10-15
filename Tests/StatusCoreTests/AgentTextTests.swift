import XCTest
@testable import StatusCore

final class AgentTextTests: XCTestCase {
    // MARK: Prompt kürzen

    func testShortPromptStaysWithLineBreaks() {
        let prompt = "Bitte die Tests ergänzen.\n\nDanach den Build prüfen."
        XCTAssertEqual(AgentText.promptExcerpt(prompt), prompt)
    }

    func testPromptOfExactlyTheLimitIsNotCut() {
        let prompt = String(repeating: "b", count: 300)
        XCTAssertEqual(AgentText.promptExcerpt(prompt), prompt)
    }

    func testLongPromptKeepsFirst300CharactersAndLineBreaks() {
        let first = String(repeating: "a", count: 99) + "\n" + String(repeating: "b", count: 200)
        let prompt = first + "REST, der wegfällt\nnoch eine Zeile"
        let excerpt = AgentText.promptExcerpt(prompt)
        XCTAssertEqual(excerpt, first + "…")
        XCTAssertEqual(excerpt?.count, 301)
        XCTAssertTrue(excerpt?.contains("\n") ?? false)
    }

    func testCutDoesNotEndInWhitespaceBeforeEllipsis() {
        let prompt = String(repeating: "c", count: 298) + "\n\n" + "danach mehr"
        XCTAssertEqual(AgentText.promptExcerpt(prompt), String(repeating: "c", count: 298) + "…")
    }

    func testCountsCharactersNotBytes() {
        // Umlaute und zusammengesetzte Emoji zählen als ein Zeichen und werden nie zerteilt.
        let prompt = String(repeating: "ä", count: 299) + "👩‍💻" + "Rest"
        XCTAssertEqual(AgentText.promptExcerpt(prompt), String(repeating: "ä", count: 299) + "👩‍💻" + "…")
    }

    func testOuterWhitespaceIsTrimmedAndEmptyIsNil() {
        XCTAssertEqual(AgentText.promptExcerpt("\n  Zeile 1\nZeile 2  \n"), "Zeile 1\nZeile 2")
        XCTAssertNil(AgentText.promptExcerpt(" \n\t"))
        XCTAssertNil(AgentText.promptExcerpt(""))
        XCTAssertNil(AgentText.promptExcerpt(nil))
    }

    func testShorteningTwiceChangesNothing() {
        for prompt in [String(repeating: "d", count: 1_000),
                       String(repeating: "e", count: 299) + " " + String(repeating: "f", count: 50)] {
            let once = AgentText.promptExcerpt(prompt)
            XCTAssertEqual(AgentText.promptExcerpt(once), once)
        }
    }

    // MARK: ~-Abkürzung

    func testHomeIsAbbreviated() {
        let home = "/Users/kollegin-a"
        XCTAssertEqual(AgentText.abbreviatingHome("/Users/kollegin-a/Development/beispiel", home: home),
                       "~/Development/beispiel")
        XCTAssertEqual(AgentText.abbreviatingHome("/Users/kollegin-a", home: home), "~")
        XCTAssertEqual(AgentText.abbreviatingHome("/Users/kollegin-a/Development/beispiel", home: home + "/"),
                       "~/Development/beispiel")
    }

    func testPathsOutsideHomeStay() {
        let home = "/Users/kollegin-a"
        XCTAssertEqual(AgentText.abbreviatingHome("/private/tmp/beispiel-1", home: home), "/private/tmp/beispiel-1")
        XCTAssertEqual(AgentText.abbreviatingHome("/Users/kollegin-ab/beispiel", home: home),
                       "/Users/kollegin-ab/beispiel")
        XCTAssertEqual(AgentText.abbreviatingHome("/Users", home: home), "/Users")
        XCTAssertEqual(AgentText.abbreviatingHome("/private/tmp/beispiel-1", home: "/"), "/private/tmp/beispiel-1")
        XCTAssertEqual(AgentText.abbreviatingHome("/private/tmp/beispiel-1", home: ""), "/private/tmp/beispiel-1")
    }
}
