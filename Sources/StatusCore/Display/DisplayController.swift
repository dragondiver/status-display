import Foundation

/// Serialisiert alles, was ans Panel geht: Init, Helligkeit, Bilder, Heartbeat.
/// Merkt sich Helligkeit und letztes Bild und stellt beides nach jedem (Re-)Connect wieder her.
public final class DisplayController {
    public enum State: Equatable { case disconnected, connected }
    public static let heartbeatInterval: TimeInterval = 5

    /// Wird auf dem Main-Thread aufgerufen.
    public var onStateChange: ((State) -> Void)?

    private let queue = DispatchQueue(label: "status-display.akp02")
    private var writer: HIDReportWriter?
    private var lastFrame: [UInt8]?
    private var brightness: Int
    private var timer: DispatchSourceTimer?

    public init(brightness: Int = 60) { self.brightness = brightness }

    public func attach(_ writer: HIDReportWriter) {
        queue.async {
            self.writer = writer
            self.initializeAndRestore()
            guard self.writer != nil else { return }
            self.startHeartbeat()
            self.publish(.connected)
        }
    }

    public func detach() { queue.async { self.drop() } }

    /// Nach dem Aufwachen: Panel kann Helligkeit und Bild verloren haben.
    public func reinitialize() { queue.async { self.initializeAndRestore() } }

    public func show(jpeg: [UInt8]) {
        queue.async {
            self.lastFrame = jpeg
            self.send(AKP02Protocol.fullFrameReports(jpeg: jpeg))
        }
    }

    public func setBrightness(_ percent: Int) {
        queue.async {
            self.brightness = percent
            self.send([AKP02Protocol.brightness(percent)])
        }
    }

    /// Wartet, bis alle bisher eingereihten Aufträge erledigt sind (für Tests und CLI).
    public func flush() { queue.sync {} }

    func beat() { queue.async { self.send([AKP02Protocol.heartbeat()]) } }

    private func initializeAndRestore() {
        send([AKP02Protocol.screenOn(), AKP02Protocol.brightness(brightness)])
        if let frame = lastFrame { send(AKP02Protocol.fullFrameReports(jpeg: frame)) }
    }

    private func send(_ reports: [[UInt8]]) {
        guard let writer else { return }
        do {
            for report in reports { try writer.write(report) }
        } catch {
            drop()
        }
    }

    private func drop() {
        let wasConnected = writer != nil
        writer = nil
        timer?.cancel()
        timer = nil
        if wasConnected { publish(.disconnected) }
    }

    private func startHeartbeat() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.heartbeatInterval, repeating: Self.heartbeatInterval)
        t.setEventHandler { [weak self] in self?.send([AKP02Protocol.heartbeat()]) }
        t.resume()
        timer = t
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }
}
