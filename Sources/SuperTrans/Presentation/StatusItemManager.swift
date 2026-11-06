import AppKit
import Combine
import SuperTransCore

public final class StatusItemManager: NSObject, NSPopoverDelegate, NSMenuDelegate {
    public private(set) var statusItem: NSStatusItem
    public private(set) var popover: NSPopover

    public weak var floatingHistoryPanel: (any FloatingPanelPresenting)?
    public var hotKeyManager: any HotKeyManaging
    public var previousAppTracker: any PreviousAppTracking
    public weak var settingsWindowController: SettingsWindowController?
    public weak var storageManager: StorageManager? {
        didSet { bindStorageManager() }
    }

    public var onTranslateShortcutRequested: (() -> Void)?
    public var onOpenSettingsRequested: (() -> Void)?
    public var onClearHistoryRequested: (() -> Void)?
    public var onCheckForUpdatesRequested: (() -> Void)?

    private var settingsObserver: AnyCancellable?
    private var lastPopoverCloseTimestamp: TimeInterval = 0

    public init(
        contentViewController: NSViewController? = nil,
        floatingHistoryPanel: (any FloatingPanelPresenting)? = nil,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        settingsWindowController: SettingsWindowController? = nil,
        storageManager: StorageManager? = nil,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.floatingHistoryPanel = floatingHistoryPanel
        self.hotKeyManager = hotKeyManager
        self.settingsWindowController = settingsWindowController
        self.storageManager = storageManager
        self.previousAppTracker = previousAppTracker

        super.init()

        configureStatusItem()
        configurePopover(with: contentViewController)
        configureHotKeys()
        bindStorageManager()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        if let img = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "SuperTrans") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = img.withSymbolConfiguration(config) ?? img
            button.image?.isTemplate = true
        } else {
            button.title = "ST"
        }
        button.target = self
        button.action = #selector(statusItemButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover(with viewController: NSViewController?) {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 600)
        if let vc = viewController {
            popover.contentViewController = vc
        }
    }

    private func configureHotKeys() {
        let settings = storageManager?.settings ?? AppSettings()
        hotKeyManager.registerTranslateHotKey(
            keyCode: settings.translateHotKeyKeyCode,
            modifiers: settings.translateHotKeyModifiers
        )
        hotKeyManager.registerHistoryHotKey(
            keyCode: settings.historyHotKeyKeyCode,
            modifiers: settings.historyHotKeyModifiers
        )

        hotKeyManager.onTranslateTrigger = { [weak self] in
            DispatchQueue.main.async {
                self?.onTranslateShortcutRequested?()
            }
        }

        hotKeyManager.onHistoryTrigger = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleFloatingHistoryPanel()
            }
        }
    }

    private func bindStorageManager() {
        settingsObserver?.cancel()
        guard let storage = storageManager else { return }
        settingsObserver = storage.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let s = self.storageManager?.settings else { return }
                self.hotKeyManager.registerTranslateHotKey(
                    keyCode: s.translateHotKeyKeyCode,
                    modifiers: s.translateHotKeyModifiers
                )
                self.hotKeyManager.registerHistoryHotKey(
                    keyCode: s.historyHotKeyKeyCode,
                    modifiers: s.historyHotKeyModifiers
                )
            }
        }
    }

    @objc private func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            presentContextMenu()
        } else {
            togglePopover()
        }
    }

    private func presentContextMenu() {
        let menu = NSMenu(title: "SuperTrans")
        let loc = LocalizationManager.shared

        let translateNowItem = NSMenuItem(
            title: loc.tr(.translateClipboardNow),
            action: #selector(translateNowClicked(_:)),
            keyEquivalent: ""
        )
        translateNowItem.target = self
        translateNowItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(translateNowItem)

        let showHistoryItem = NSMenuItem(
            title: loc.tr(.showTranslationHistory),
            action: #selector(showHistoryClicked(_:)),
            keyEquivalent: ""
        )
        showHistoryItem.target = self
        showHistoryItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(showHistoryItem)

        let autoTranslateItem = NSMenuItem(
            title: loc.tr(.autoTranslateOnCopy),
            action: #selector(toggleAutoTranslateClicked(_:)),
            keyEquivalent: ""
        )
        autoTranslateItem.target = self
        autoTranslateItem.state = (storageManager?.settings.autoTranslateEveryCopy == true) ? .on : .off
        autoTranslateItem.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        menu.addItem(autoTranslateItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: loc.tr(.preferences),
            action: #selector(openSettingsClicked(_:)),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefsItem)

        let checkUpdateItem = NSMenuItem(
            title: loc.languageCode == "vi" ? "Kiểm tra bản cập nhật..." : "Check for Updates...",
            action: #selector(checkForUpdatesClicked(_:)),
            keyEquivalent: ""
        )
        checkUpdateItem.target = self
        checkUpdateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(checkUpdateItem)

        let clearItem = NSMenuItem(
            title: loc.tr(.clearUnpinnedHistory),
            action: #selector(clearHistoryClicked(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: loc.tr(.quitApp),
            action: #selector(quitClicked(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    public func togglePopover() {
        let now = ProcessInfo.processInfo.systemUptime
        if popover.isShown {
            closePopover()
        } else if now - lastPopoverCloseTimestamp > 0.15 {
            showPopover()
        }
    }

    public func showPopover() {
        floatingHistoryPanel?.dismiss()
        previousAppTracker.captureFrontmostApplication()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closePopover() {
        DualPreviewPanel.shared.hide(immediate: true)
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    public func toggleFloatingHistoryPanel() {
        guard let panel = floatingHistoryPanel else { return }
        if panel.isVisible {
            panel.dismiss()
        } else {
            closePopover()
            panel.show(near: NSEvent.mouseLocation)
        }
    }

    public func dismissAll() {
        closePopover()
        floatingHistoryPanel?.dismiss()
        DualPreviewPanel.shared.hide(immediate: true)
    }

    public func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTimestamp = ProcessInfo.processInfo.systemUptime
        DualPreviewPanel.shared.hide(immediate: true)
    }

    @objc private func translateNowClicked(_ sender: Any?) {
        onTranslateShortcutRequested?()
    }

    @objc private func showHistoryClicked(_ sender: Any?) {
        showPopover()
    }

    @objc private func toggleAutoTranslateClicked(_ sender: Any?) {
        guard let storage = storageManager else { return }
        var s = storage.settings
        s.autoTranslateEveryCopy.toggle()
        storage.settings = s
    }

    @objc private func openSettingsClicked(_ sender: Any?) {
        onOpenSettingsRequested?()
    }

    @objc private func clearHistoryClicked(_ sender: Any?) {
        onClearHistoryRequested?()
    }

    @objc private func checkForUpdatesClicked(_ sender: Any?) {
        onCheckForUpdatesRequested?()
    }

    @objc private func quitClicked(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
