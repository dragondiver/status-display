import XCTest
@testable import StatusCore

final class RGBColorTests: XCTestCase {
    func testHexRoundTrip() {
        let c = RGBColor(hex: "#B3263E")!
        XCTAssertEqual(c.hex, "#B3263E")
        XCTAssertEqual(c.r, 0xB3 / 255.0, accuracy: 0.0001)
    }
    func testHexWithoutHashAndInvalid() {
        XCTAssertEqual(RGBColor(hex: "00ff00")?.hex, "#00FF00")
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: "zzzzzz"))
    }
}
