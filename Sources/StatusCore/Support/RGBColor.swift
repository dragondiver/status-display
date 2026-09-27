import CoreGraphics
import Foundation

public struct RGBColor: Codable, Equatable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public func withAlpha(_ alpha: Double) -> RGBColor { RGBColor(r: r, g: g, b: b, a: alpha) }
}
