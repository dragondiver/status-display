import XCTest
@testable import StatusCore

final class StatusMenuBuilderTests: XCTestCase {
    func testDurationChoicesHaveFiveEntriesInMenuOrder() {
        let titles = StatusMenuBuilder.durationChoices.map(\.title)
        XCTAssertEqual(titles, ["Ohne Ende", "30 Minuten", "1 Stunde", "2 Stunden", "Bis Tagesende"])
    }

    func testDurationChoicesCarryTheRightDurations() {
        let choices = StatusMenuBuilder.durationChoices
        XCTAssertEqual(choices[0].duration, nil)
        XCTAssertEqual(choices[0].untilEndOfDay, false)
        XCTAssertEqual(choices[1].duration, 1800)
        XCTAssertEqual(choices[2].duration, 3600)
        XCTAssertEqual(choices[3].duration, 7200)
        XCTAssertEqual(choices[4].duration, nil)
        XCTAssertEqual(choices[4].untilEndOfDay, true)
    }

    /// „Ohne Ende“ und „Bis Tagesende“ haben beide `duration == nil` – sie unterscheiden sich nur
    /// über `untilEndOfDay`. Ein Regressionstest, falls das mal verwechselt wird.
    func testOnlyLastChoiceIsUntilEndOfDay() {
        let flags = StatusMenuBuilder.durationChoices.map(\.untilEndOfDay)
        XCTAssertEqual(flags, [false, false, false, false, true])
    }

    func testEntriesCoverAllPresetsInOrder() {
        let entries = StatusMenuBuilder.entries(presets: StatusPreset.defaults)
        XCTAssertEqual(entries.map(\.presetID), StatusPreset.defaults.map(\.id))
        XCTAssertEqual(entries.map(\.presetName), StatusPreset.defaults.map(\.name))
    }

    func testEveryEntryGetsAllFiveDurationChoices() {
        let entries = StatusMenuBuilder.entries(presets: StatusPreset.defaults)
        for entry in entries {
            XCTAssertEqual(entry.choices, StatusMenuBuilder.durationChoices)
        }
    }

    func testEntriesForEmptyPresetsIsEmpty() {
        XCTAssertEqual(StatusMenuBuilder.entries(presets: []), [])
    }

    func testEntriesForSinglePresetKeepsItsNameAndID() {
        let preset = StatusPreset(id: "custom", name: "Custom", colorHex: "#123456")
        let entries = StatusMenuBuilder.entries(presets: [preset])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].presetID, "custom")
        XCTAssertEqual(entries[0].presetName, "Custom")
    }
}
