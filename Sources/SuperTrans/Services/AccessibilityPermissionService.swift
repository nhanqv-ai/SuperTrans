import AppKit
import ApplicationServices

public protocol AccessibilityPermissionServicing: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func checkAccessibilityPermission() -> Bool
    @discardableResult
    func requestAccessibilityPermission() -> Bool
    @discardableResult
    func resetAndRequestAccessibilityPermission() -> Bool
    func openAccessibilitySettings()
}

public final class AccessibilityPermissionService: AccessibilityPermissionServicing, @unchecked Sendable {
    public static let shared = AccessibilityPermissionService()

    public init() {}

    public var isAccessibilityTrusted: Bool {
        return AXIsProcessTrusted()
    }

    public func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openAccessibilitySettings()
        }
        return trusted
    }

    @discardableResult
    public func resetAndRequestAccessibilityPermission() -> Bool {
        if !AXIsProcessTrusted() {
            let bundleId = Bundle.main.bundleIdentifier ?? "com.nhanqv.supertrans"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleId]
            try? process.run()
            process.waitUntilExit()
        }
        return requestAccessibilityPermission()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
