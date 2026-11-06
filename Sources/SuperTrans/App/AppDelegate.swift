import AppKit
import SwiftUI
import SuperTransCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public var storageManager: StorageManager!
    public var pasteboardMonitor: PasteboardMonitor!
    public var pasteboardWriter: PasteboardWriter!
    public var sessionController: TranslationSessionController!
    public var cursorTranslationPanel: CursorTranslationPanel!
    public var floatingHistoryPanel: FloatingHistoryPanel!
    public var statusItemManager: StatusItemManager!
    public var settingsWindowController: SettingsWindowController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installStandardEditMenuIfNeeded()

        storageManager = StorageManager()
        pasteboardMonitor = PasteboardMonitor.shared
        pasteboardWriter = PasteboardWriter(pasteboard: .general, monitor: pasteboardMonitor)

        LaunchAtLoginManager.shared.setEnabled(storageManager.settings.launchAtLogin)

        // Configure PasteboardMonitor
        pasteboardMonitor.maxThumbnailPixelSize = storageManager.settings.maxThumbnailPixelSize
        pasteboardMonitor.isIgnoredAppCheck = { [weak self] bundleId, name in
            self?.storageManager.isAppIgnored(bundleIdentifier: bundleId, name: name) ?? false
        }
        pasteboardMonitor.onCopyDetected = { [weak self] payload, isDoubleCopy in
            guard let self = self else { return }
            let settings = self.storageManager.settings
            let shouldTrigger = (isDoubleCopy && settings.enableDoubleCopyTrigger) || settings.autoTranslateEveryCopy
            guard shouldTrigger else { return }

            DispatchQueue.main.async {
                self.presentTranslationPopup(with: payload, at: NSEvent.mouseLocation)
            }
        }
        pasteboardMonitor.startPolling(intervalMs: storageManager.settings.pollIntervalMs)

        // Initialize SettingsWindowController
        settingsWindowController = SettingsWindowController(
            storageManager: storageManager,
            hotKeyManager: HotKeyManager.shared,
            onPresentationDismissalRequested: { [weak self] in
                self?.statusItemManager?.dismissAll()
            }
        )
        SettingsWindowController.shared = settingsWindowController

        // Initialize Cursor Translation Session & Panel
        sessionController = TranslationSessionController(
            storageManager: storageManager,
            geminiClient: GeminiClient.shared,
            pasteboardWriter: pasteboardWriter,
            autoPasteService: AutoPasteService.shared,
            previousAppTracker: PreviousAppTracker.shared
        )
        sessionController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        cursorTranslationPanel = CursorTranslationPanel(sessionController: sessionController)
        cursorTranslationPanel.setRootView(CursorPopupView(controller: sessionController))

        // Initialize MainHistoryView for Menu Bar Popover and Floating History Panel
        let historyView = MainHistoryView(
            storageManager: storageManager,
            pasteboardWriter: pasteboardWriter,
            autoPasteService: AutoPasteService.shared,
            previousAppTracker: PreviousAppTracker.shared,
            onDismiss: { [weak self] in
                self?.statusItemManager.dismissAll()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onTranslateClipboardNow: { [weak self] in
                self?.triggerTranslateSelectionOrClipboard()
            },
            onOpenItemInPopup: { [weak self] item in
                guard let self = self else { return }
                self.sessionController.presentExistingItem(item)
                self.cursorTranslationPanel.presentAboveCursor(at: NSEvent.mouseLocation)
            },
            onRetranslateItem: { [weak self] item in
                guard let self = self else { return }
                self.retranslateHistoryItem(item)
            }
        )

        floatingHistoryPanel = FloatingHistoryPanel(
            size: NSSize(width: 390, height: 600),
            rootView: historyView
        )

        let popoverVC = NSHostingController(rootView: historyView)
        popoverVC.preferredContentSize = NSSize(width: 390, height: 600)

        statusItemManager = StatusItemManager(
            contentViewController: popoverVC,
            floatingHistoryPanel: floatingHistoryPanel,
            hotKeyManager: HotKeyManager.shared,
            settingsWindowController: settingsWindowController,
            storageManager: storageManager,
            previousAppTracker: PreviousAppTracker.shared
        )

        floatingHistoryPanel.onDismiss = { [weak self] in
            self?.statusItemManager.dismissAll()
        }

        statusItemManager.onTranslateShortcutRequested = { [weak self] in
            self?.triggerTranslateSelectionOrClipboard()
        }

        statusItemManager.onOpenSettingsRequested = { [weak self] in
            self?.openSettings()
        }

        statusItemManager.onClearHistoryRequested = { [weak self] in
            self?.storageManager.clearUnpinnedHistory()
        }
    }

    public func triggerTranslateSelectionOrClipboard() {
        let mouseAnchor = NSEvent.mouseLocation
        PreviousAppTracker.shared.captureFrontmostApplication()
        statusItemManager?.dismissAll()

        let maxThumb = storageManager.settings.maxThumbnailPixelSize
        SelectionGrabber.shared.grabSelectionOrClipboard(
            pasteboardMonitor: pasteboardMonitor,
            maxThumbnailPixelSize: maxThumb
        ) { [weak self] payload in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let payload = payload {
                    self.presentTranslationPopup(with: payload, at: mouseAnchor)
                } else {
                    self.sessionController.payload = nil
                    self.sessionController.state = .failed(
                        message: LocalizationManager.shared.tr(.errorEmptyInput),
                        isMissingKey: false
                    )
                    self.cursorTranslationPanel.presentAboveCursor(at: mouseAnchor)
                }
            }
        }
    }

    public func presentTranslationPopup(with payload: ClipboardPayload, at mouseLocation: NSPoint) {
        statusItemManager?.dismissAll()
        sessionController.startTranslation(payload: payload)
        cursorTranslationPanel.presentAboveCursor(at: mouseLocation)
    }

    public func retranslateHistoryItem(_ item: TranslationItem) {
        let mouseAnchor = NSEvent.mouseLocation
        switch item.contentType {
        case .text:
            let payload: ClipboardPayload = .text(item.sourceText ?? item.translatedText)
            sessionController.startTranslation(
                payload: payload,
                overrideTargetLanguage: item.targetLanguage,
                existingItemId: item.id
            )
            cursorTranslationPanel.presentAboveCursor(at: mouseAnchor)
        case .image:
            if let imgData = storageManager.getImageData(for: item) {
                let payload: ClipboardPayload = .image(
                    pngData: imgData,
                    thumbData: imgData,
                    width: item.imageWidth ?? 0,
                    height: item.imageHeight ?? 0
                )
                sessionController.startTranslation(
                    payload: payload,
                    overrideTargetLanguage: item.targetLanguage,
                    existingItemId: item.id
                )
                cursorTranslationPanel.presentAboveCursor(at: mouseAnchor)
            }
        }
    }

    public func openSettings() {
        statusItemManager?.dismissAll()
        settingsWindowController?.showSettings()
    }

    private func installStandardEditMenuIfNeeded() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()

        // Ensure Edit menu with Cut/Copy/Paste/SelectAll exists so Cmd+V works in all TextFields in LSUIElement mode
        let hasPasteItem = mainMenu.items.contains { topItem in
            topItem.submenu?.items.contains(where: { $0.keyEquivalent == "v" }) == true
        }
        guard !hasPasteItem else { return }

        if mainMenu.items.isEmpty {
            let appMenuItem = NSMenuItem()
            let appMenu = NSMenu(title: "SuperTrans")
            appMenu.addItem(withTitle: "Quit SuperTrans", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)
        }

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor?.stopPolling()
        statusItemManager?.hotKeyManager.unregisterAll()
        statusItemManager?.dismissAll()
        cursorTranslationPanel?.dismiss()
        storageManager?.flushDiskQueue()
    }
}
