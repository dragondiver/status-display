import Foundation
import IOKit.hid

public protocol HIDReportWriter: AnyObject {
    func write(_ report: [UInt8]) throws
}

public enum AKP02Error: Error, Equatable {
    case writeFailed(Int32)
}

final class IOHIDWriter: HIDReportWriter {
    let device: IOHIDDevice
    init(device: IOHIDDevice) { self.device = device }

    func write(_ report: [UInt8]) throws {
        let result = report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf.baseAddress!, buf.count)
        }
        if result != kIOReturnSuccess { throw AKP02Error.writeFailed(result) }
    }
}

/// Findet das AKP02 über IOHIDManager und meldet An- und Abstecken (Callbacks auf dem Main-Runloop).
///
/// Der Aufrufer muss die Instanz am Leben erhalten, solange sie gestartet ist: `start()` reicht
/// `self` als unretained Kontext an IOKit-Callbacks weiter, die während des Laufs der Runloop
/// jederzeit feuern können.
public final class AKP02Transport {
    public var onConnect: ((HIDReportWriter) -> Void)?
    public var onDisconnect: (() -> Void)?
    private let manager: IOHIDManager
    private var current: IOHIDDevice?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: AKP02Protocol.vendorID,
                                    kIOHIDProductIDKey: AKP02Protocol.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
    }

    @discardableResult
    public func start() -> IOReturn {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<AKP02Transport>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<AKP02Transport>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        guard current == nil else { return } // dasselbe Gerät meldet sich je Usage
        current = device
        onConnect?(IOHIDWriter(device: device))
    }

    private func detach(_ device: IOHIDDevice) {
        guard let current, CFEqual(current, device) else { return }
        self.current = nil
        onDisconnect?()
    }
}
