import XCTest
import CoreGraphics
@testable import StatusCore

final class PanelImageTests: XCTestCase {
    /// Querformat 1920×462, blau, rotes 50×50-Quadrat oben links.
    private func landscapeWithRedCorner() -> CGImage {
        let ctx = PanelImage.makeContext(width: 1920, height: 462)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 462))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 462 - 50, width: 50, height: 50)) // CG: Ursprung unten links
        return ctx.makeImage()!
    }

    func testRotationIsClockwiseIntoPortrait() {
        let rotated = PanelImage.rotateForPanel(landscapeWithRedCorner())
        XCTAssertEqual(rotated.width, 462)
        XCTAssertEqual(rotated.height, 1920)
        XCTAssertTrue(isRed(pixel(rotated, 440, 10)), "oben links im Querformat → oben rechts im Hochformat")
        XCTAssertTrue(isBlue(pixel(rotated, 10, 10)))
    }

    func testJPEGHasJPEGMagic() {
        let bytes = PanelImage.encode(landscape: landscapeWithRedCorner())
        XCTAssertEqual(Array(bytes.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertLessThan(bytes.count, 500_000)
    }
}
