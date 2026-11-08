import AppKit
import Combine
import SwiftUI
import SuperTransCore

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static var shared: SettingsWindowController?

    public let storageManager: StorageManager
    public let hotKeyManager: any HotKeyManaging
    public var onPresentationDismissalRequested: (() -> Void)?
    private var hasBeenCentered: Bool = false
    private var languageCancellable: AnyCancellable?

    public init(
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        onPresentationDismissalRequested: (() -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.onPresentationDismissalRequested = onPresentationDismissalRequested

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 510, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperTrans — " + LocalizationManager.shared.tr(.preferences)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.setContentSize(NSSize(width: 510, height: 500))
        window.setFrameAutosaveName("SuperTransSettingsWindow")

        super.init(window: window)
        window.delegate = self
        setupContentView()

        languageCancellable = LocalizationManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.window?.title = "SuperTrans — " + LocalizationManager.shared.tr(.preferences)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setupContentView() {
        guard let window = self.window else { return }
        let settingsView = SettingsView(
            storageManager: storageManager,
            hotKeyManager: hotKeyManager,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.preferredContentSize = NSSize(width: 510, height: 500)
        window.contentViewController = hostingController
    }

    public func showSettings() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
            return
        }

        onPresentationDismissalRequested?()
        guard let window = self.window else { return }
        window.title = "SuperTrans — " + LocalizationManager.shared.tr(.preferences)
        if !hasBeenCentered && !window.isVisible {
            window.center()
            hasBeenCentered = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        setupContentView()
    }
}
