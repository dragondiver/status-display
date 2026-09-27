import Foundation

/// Kleiner threadsicherer Wert für Daten, die Server-Queue und Main-Thread teilen.
public final class Locked<Value> {
    private var stored: Value
    private let lock = NSLock()
    public init(_ value: Value) { stored = value }
    public var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    public func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
