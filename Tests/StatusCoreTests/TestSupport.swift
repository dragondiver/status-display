import CoreGraphics
@testable import StatusCore

/// Liest ein Pixel, Koordinaten von oben links.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    var buffer = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (buffer[0], buffer[1], buffer[2])
}

func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

final class FakeWriter: HIDReportWriter {
    var reports: [[UInt8]] = []
    var failWhenCountReaches: Int?
    func write(_ report: [UInt8]) throws {
        if let limit = failWhenCountReaches, reports.count >= limit { throw AKP02Error.writeFailed(-1) }
        reports.append(report)
    }
}
