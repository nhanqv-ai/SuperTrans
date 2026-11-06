import AppKit
import SwiftUI
import SuperTransCore

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static var shared: SettingsWindowController?

    public let storageManager: StorageManager
    public let hotKeyManager: any HotKeyManaging
    public var onPresentationDismissalRequested: (() -> Void)?

    public init(
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        onPresentationDismissalRequested: (() -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.onPresentationDismissalRequested = onPresentationDismissalRequested

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperTrans Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let settingsView = SettingsView(
            storageManager: storageManager,
            hotKeyManager: hotKeyManager
        )
        window.contentViewController = NSHostingController(rootView: settingsView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showSettings() {
        onPresentationDismissalRequested?()
        guard let window = self.window else { return }
        window.title = LocalizationManager.shared.tr(.preferences)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
