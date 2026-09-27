import CoreGraphics
import Foundation
import StatusCore

enum CLI {
    /// Zeigt 15 s lang vier Farbfelder auf dem Panel. Prüft Gerätezugriff ohne App.
    static func displayTest() -> Int32 {
        let ctx = PanelImage.makeContext(width: 1920, height: 462)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.7, 0.15, 0.24), (0.35, 0.78, 0.47), (0.94, 0.7, 0.24), (0.18, 0.43, 0.71)]
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fill(CGRect(x: i * 480, y: 0, width: 480, height: 462))
        }
        let jpeg = PanelImage.encode(landscape: ctx.makeImage()!)
        let controller = DisplayController(brightness: 60)
        let transport = AKP02Transport()
        var everConnected = false
        controller.onStateChange = { state in
            if state == .connected { everConnected = true }
            print(state == .connected ? "Display verbunden" : "Display getrennt")
        }
        transport.onConnect = { controller.attach($0); controller.show(jpeg: jpeg) }
        transport.onDisconnect = { controller.detach() }
        let openResult = transport.start()
        guard openResult == kIOReturnSuccess else {
            print(String(format: "HID-Manager konnte nicht geöffnet werden (IOReturn %#x)", openResult))
            return 1
        }
        withExtendedLifetime(transport) {
            RunLoop.main.run(until: Date().addingTimeInterval(15))
        }
        if !everConnected { print("Kein AKP02 gefunden (0300:3017)") }
        return everConnected ? 0 : 1
    }
}
