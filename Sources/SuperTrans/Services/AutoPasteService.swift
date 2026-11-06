import AppKit
import ApplicationServices

public protocol AutoPasteServicing: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityPermission() -> Bool
    @discardableResult
    func resetAndRequestAccessibilityPermission() -> Bool
    func openAccessibilitySettings()
    @discardableResult
    func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval,
        completion: (() -> Void)?
    ) -> Bool
}

public final class AutoPasteService: AutoPasteServicing, @unchecked Sendable {
    public static let shared = AutoPasteService()

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

    @discardableResult
    public func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval = 0.04,
        completion: (() -> Void)? = nil
    ) -> Bool {
        guard AXIsProcessTrusted() else {
            completion?()
            return false
        }

        if let app = targetApp, !app.isTerminated {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay)) {
            let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
            if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            completion?()
        }
        return true
    }
}
