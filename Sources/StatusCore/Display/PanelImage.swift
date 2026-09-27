import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PanelImage {
    public static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    /// Dreht ein 1920×462-Querformatbild 90° im Uhrzeigersinn in den 462×1920-Puffer des Panels.
    public static func rotateForPanel(_ landscape: CGImage) -> CGImage {
        let ctx = makeContext(width: AKP02Protocol.shortSide, height: AKP02Protocol.longSide)
        ctx.translateBy(x: 0, y: CGFloat(AKP02Protocol.longSide))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(landscape, in: CGRect(x: 0, y: 0, width: landscape.width, height: landscape.height))
        return ctx.makeImage()!
    }

    public static func jpeg(_ image: CGImage, quality: Double = 0.85) -> [UInt8] {
        encode(image, type: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    public static func png(_ image: CGImage) -> Data {
        Data(encode(image, type: .png, options: [:]))
    }

    public static func encode(landscape: CGImage) -> [UInt8] {
        jpeg(rotateForPanel(landscape))
    }

    private static func encode(_ image: CGImage, type: UTType, options: [CFString: Any]) -> [UInt8] {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        CGImageDestinationFinalize(dest)
        return [UInt8](data as Data)
    }
}
