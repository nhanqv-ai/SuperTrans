import AppKit

public protocol PreviousAppTracking: AnyObject {
    var previousApp: NSRunningApplication? { get }
    func captureFrontmostApplication()
    func clear()
}

public final class PreviousAppTracker: PreviousAppTracking, @unchecked Sendable {
    public static let shared = PreviousAppTracker()

    private let lock = NSLock()
    private var _previousApp: NSRunningApplication?

    public var previousApp: NSRunningApplication? {
        lock.lock()
        defer { lock.unlock() }
        return _previousApp
    }

    public init() {}

    public func captureFrontmostApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let myBundleId = Bundle.main.bundleIdentifier ?? "com.nhanqv.supertrans"
        if frontmost.bundleIdentifier != myBundleId && frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lock.lock()
            _previousApp = frontmost
            lock.unlock()
        }
    }

    public func clear() {
        lock.lock()
        _previousApp = nil
        lock.unlock()
    }
}
