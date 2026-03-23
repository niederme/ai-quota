import Foundation

// Simple lock-isolated counter for test use
final class LockIsolated<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    init(_ value: T) { _value = value }
    var value: T { lock.withLock { _value } }
    @discardableResult
    func withLock<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&_value) } }
}
