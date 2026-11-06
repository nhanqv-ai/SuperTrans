import AppKit
import SwiftUI
import Combine
import SuperTransCore

public enum TranslationPopupState: Equatable {
    case idle
    case translating
    case completed(translatedText: String, modelUsed: String, keyMasked: String)
    case failed(message: String, isMissingKey: Bool)
}

public final class TranslationSessionController: ObservableObject {
    @Published public var state: TranslationPopupState = .idle
    @Published public var payload: ClipboardPayload?
    @Published public var targetLanguage: String = AppSettings.defaultTargetLanguage
    @Published public var isPinned: Bool = false
    @Published public var showOriginalContent: Bool = false
    @Published public var didCopyFeedback: Bool = false

    public var currentHistoryItemId: UUID?
    private var activeTask: Task<Void, Never>?

    public let storageManager: StorageManager
    public let geminiClient: any GeminiTranslating
    public let pasteboardWriter: any PasteboardWriting
    public let autoPasteService: any AutoPasteServicing
    public let previousAppTracker: any PreviousAppTracking

    public var onOpenSettings: (() -> Void)?
    public var onDismissPopup: (() -> Void)?
    public var onContentSizeChanged: (() -> Void)?

    public init(
        storageManager: StorageManager,
        geminiClient: any GeminiTranslating = GeminiClient.shared,
        pasteboardWriter: any PasteboardWriting,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared
    ) {
        self.storageManager = storageManager
        self.geminiClient = geminiClient
        self.pasteboardWriter = pasteboardWriter
        self.autoPasteService = autoPasteService
        self.previousAppTracker = previousAppTracker
        self.targetLanguage = storageManager.settings.targetLanguage
    }

    public func startTranslation(
        payload: ClipboardPayload,
        overrideTargetLanguage: String? = nil,
        existingItemId: UUID? = nil,
        forceRefresh: Bool = false
    ) {
        activeTask?.cancel()
        self.payload = payload
        self.currentHistoryItemId = existingItemId
        self.didCopyFeedback = false
        let lang = overrideTargetLanguage ?? storageManager.settings.targetLanguage
        self.targetLanguage = lang

        // Check History Cache first when not forcing a re-translation
        if !forceRefresh, case .text(let sourceText) = payload,
           let cachedItem = storageManager.findCachedTranslation(sourceText: sourceText, targetLanguage: lang) {
            self.currentHistoryItemId = cachedItem.id
            self.storageManager.touchItem(id: cachedItem.id)
            self.state = .completed(
                translatedText: cachedItem.translatedText,
                modelUsed: cachedItem.modelUsed ?? storageManager.settings.selectedModel,
                keyMasked: "History Cache"
            )
            self.onContentSizeChanged?()
            return
        }

        self.state = .translating
        self.onContentSizeChanged?()

        let currentSettings = storageManager.settings
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let response: GeminiTranslationResponse
                switch payload {
                case .text(let sourceText):
                    response = try await self.geminiClient.translateText(
                        sourceText,
                        targetLanguage: lang,
                        settings: currentSettings
                    )
                case .image(let pngData, _, _, _):
                    response = try await self.geminiClient.translateImage(
                        imageData: pngData,
                        mimeType: "image/png",
                        targetLanguage: lang,
                        settings: currentSettings
                    )
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.state = .completed(
                        translatedText: response.translatedText,
                        modelUsed: response.modelUsed,
                        keyMasked: response.keyUsedMasked
                    )
                    self.persistResult(
                        payload: payload,
                        translatedText: response.translatedText,
                        targetLanguage: lang,
                        modelUsed: response.modelUsed
                    )
                    self.onContentSizeChanged?()
                }
            } catch let err as GeminiError {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let isMissingKey = (err == .missingAPIKey)
                    self.state = .failed(
                        message: err.errorDescription ?? "Translation error",
                        isMissingKey: isMissingKey
                    )
                    self.onContentSizeChanged?()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.state = .failed(
                        message: error.localizedDescription,
                        isMissingKey: false
                    )
                    self.onContentSizeChanged?()
                }
            }
        }
    }

    public func presentExistingItem(_ item: TranslationItem) {
        activeTask?.cancel()
        self.currentHistoryItemId = item.id
        self.targetLanguage = item.targetLanguage
        self.didCopyFeedback = false
        switch item.contentType {
        case .text:
            self.payload = .text(item.sourceText ?? "")
        case .image:
            if let imgData = storageManager.getImageData(for: item) {
                self.payload = .image(
                    pngData: imgData,
                    thumbData: imgData,
                    width: item.imageWidth ?? 0,
                    height: item.imageHeight ?? 0
                )
            } else {
                self.payload = nil
            }
        }
        self.state = .completed(
            translatedText: item.translatedText,
            modelUsed: item.modelUsed ?? storageManager.settings.selectedModel,
            keyMasked: ""
        )
        self.onContentSizeChanged?()
    }

    public func retranslate(newTargetLanguage: String? = nil) {
        guard let payload = payload else { return }
        let lang = newTargetLanguage ?? targetLanguage
        // If user clicked "Dịch lại" (newTargetLanguage == nil), force a fresh API request.
        // If user switched target language in the dropdown, check cache first for that language.
        let shouldForceRefresh = (newTargetLanguage == nil)
        startTranslation(
            payload: payload,
            overrideTargetLanguage: lang,
            existingItemId: shouldForceRefresh ? currentHistoryItemId : nil,
            forceRefresh: shouldForceRefresh
        )
    }

    public func selectPromptPresetAndRetranslate(_ newPrompt: String) {
        var s = storageManager.settings
        s.customSystemPrompt = newPrompt
        storageManager.settings = s
        objectWillChange.send()
        retranslate()
    }

    public func copyTranslationAndDismiss(shouldDismiss: Bool = true) {
        guard case .completed(let translatedText, _, _) = state else { return }
        _ = pasteboardWriter.writeText(translatedText)
        didCopyFeedback = true
        if shouldDismiss && !isPinned {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.onDismissPopup?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.didCopyFeedback = false
            }
        }
    }

    public func autoPasteTranslationAndDismiss() {
        guard case .completed(let translatedText, _, _) = state else { return }
        _ = pasteboardWriter.writeText(translatedText)
        let targetApp = previousAppTracker.previousApp
        onDismissPopup?()
        if autoPasteService.isAccessibilityTrusted {
            _ = autoPasteService.pasteToActiveApp(targetApp: targetApp, delay: 0.04, completion: nil)
        }
    }

    public func cancelActiveTask() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func persistResult(
        payload: ClipboardPayload,
        translatedText: String,
        targetLanguage: String,
        modelUsed: String
    ) {
        if let existingId = currentHistoryItemId {
            storageManager.updateTranslation(
                id: existingId,
                translatedText: translatedText,
                targetLanguage: targetLanguage,
                modelUsed: modelUsed
            )
            return
        }

        switch payload {
        case .text(let srcText):
            let item = TranslationItem(
                contentType: .text,
                sourceText: srcText,
                translatedText: translatedText,
                targetLanguage: targetLanguage,
                modelUsed: modelUsed,
                byteSize: srcText.utf8.count
            )
            currentHistoryItemId = item.id
            storageManager.addTranslation(item: item, imageData: nil, thumbData: nil)

        case .image(let pngData, let thumbData, let width, let height):
            let id = UUID()
            let item = TranslationItem(
                id: id,
                contentType: .image,
                sourceText: nil,
                translatedText: translatedText,
                targetLanguage: targetLanguage,
                modelUsed: modelUsed,
                imageFileName: "\(id.uuidString).png",
                thumbnailFileName: "\(id.uuidString)_thumb.png",
                imageWidth: width,
                imageHeight: height,
                byteSize: pngData.count
            )
            currentHistoryItemId = item.id
            storageManager.addTranslation(item: item, imageData: pngData, thumbData: thumbData)
        }
    }
}

/// Floating resizable NSPanel appearing immediately above the mouse cursor when translating.
public final class CursorTranslationPanel: NSPanel, NSWindowDelegate {
    public static let defaultWidth: CGFloat = 420
    public static let minWidth: CGFloat = 340
    public static let maxWidth: CGFloat = 1400
    public static let minHeight: CGFloat = 165
    public static let maxHeight: CGFloat = 1200

    public let sessionController: TranslationSessionController

    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var anchorMouseLocation: NSPoint = .zero
    private var isDismissing: Bool = false
    private var isApplyingProgrammaticFrame: Bool = false
    private var hasUserCustomPosition: Bool = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(sessionController: TranslationSessionController) {
        self.sessionController = sessionController
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 185),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        setupPanel()
    }

    private func setupPanel() {
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow
        self.minSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        self.maxSize = NSSize(width: Self.maxWidth, height: Self.maxHeight)
        self.delegate = self

        sessionController.onDismissPopup = { [weak self] in
            self?.dismiss()
        }
        sessionController.onContentSizeChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.recalculateFrameIfVisible()
            }
        }
    }

    public func setRootView<V: View>(_ view: V) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentViewController = hosting
    }

    public func presentAboveCursor(at mouseLocation: NSPoint? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.presentAboveCursor(at: mouseLocation)
            }
            return
        }

        sessionController.previousAppTracker.captureFrontmostApplication()

        let fittingSize = computeTargetSize()
        let targetFrame: NSRect

        // When pinned and already visible, lock popup at its current screen position
        if self.isVisible && sessionController.isPinned {
            targetFrame = computeFrameKeepingCurrentTopLeft(for: fittingSize)
        } else {
            let cursorPoint = mouseLocation ?? NSEvent.mouseLocation
            self.anchorMouseLocation = cursorPoint
            self.hasUserCustomPosition = false
            targetFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
                mouseLoc: cursorPoint,
                panelSize: fittingSize
            )
        }

        applyProgrammaticFrame(targetFrame)
        self.isDismissing = false
        installMonitors()
        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.invalidateShadow()
    }

    public func recalculateFrameIfVisible() {
        guard isVisible, !inLiveResize else { return }
        let newSize = computeTargetSize()
        let targetFrame: NSRect

        if sessionController.isPinned || hasUserCustomPosition {
            targetFrame = computeFrameKeepingCurrentTopLeft(for: newSize)
        } else {
            targetFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
                mouseLoc: anchorMouseLocation,
                panelSize: newSize
            )
        }
        applyProgrammaticFrame(targetFrame)
        self.invalidateShadow()
    }

    private func applyProgrammaticFrame(_ frame: NSRect) {
        isApplyingProgrammaticFrame = true
        self.setFrame(frame, display: true)
        isApplyingProgrammaticFrame = false
    }

    private func computeFrameKeepingCurrentTopLeft(for newSize: NSSize) -> NSRect {
        let current = self.frame
        var originX = current.origin.x
        var originY = current.maxY - newSize.height

        let screen = self.screen ?? CursorPopupFrameCalculator.findScreen(for: current.origin)
        if let visibleFrame = screen?.visibleFrame {
            if originX + newSize.width > visibleFrame.maxX - 6 {
                originX = max(visibleFrame.minX + 6, visibleFrame.maxX - newSize.width - 6)
            }
            if originX < visibleFrame.minX + 6 {
                originX = visibleFrame.minX + 6
            }
            if originY < visibleFrame.minY + 6 {
                originY = visibleFrame.minY + 6
            }
            if originY + newSize.height > visibleFrame.maxY - 6 {
                originY = max(visibleFrame.minY + 6, visibleFrame.maxY - newSize.height - 6)
            }
        }

        return NSRect(
            x: round(originX),
            y: round(originY),
            width: newSize.width,
            height: newSize.height
        )
    }

    private func computeTargetSize() -> NSSize {
        let settings = sessionController.storageManager.settings
        let savedWidth = settings.popupWidth.map { CGFloat($0) }
        let width = max(Self.minWidth, min(savedWidth ?? Self.defaultWidth, Self.maxWidth))

        if let savedHeight = settings.popupHeight {
            let clampedHeight = max(Self.minHeight, min(CGFloat(savedHeight), Self.maxHeight))
            return NSSize(width: width, height: clampedHeight)
        }

        switch sessionController.state {
        case .idle, .translating:
            return NSSize(width: width, height: 165)
        case .failed:
            return NSSize(width: width, height: 185)
        case .completed(let translatedText, _, _):
            let charCount = translatedText.count
            let lineCount = translatedText.components(separatedBy: .newlines).count
            let estimatedTextHeight = max(56, min(280, CGFloat((charCount / 48) + lineCount) * 20))
            let originalExtra: CGFloat = sessionController.showOriginalContent ? 110 : 0
            let totalHeight = min(480, max(185, 128 + estimatedTextHeight + originalExtra))
            return NSSize(width: width, height: totalHeight)
        }
    }

    // MARK: - NSWindowDelegate (User Move & Live Resize Persistence)

    public func windowDidMove(_ notification: Notification) {
        guard !isApplyingProgrammaticFrame, isVisible else { return }
        hasUserCustomPosition = true
    }

    public func windowDidResize(_ notification: Notification) {
        guard !isApplyingProgrammaticFrame, isVisible, inLiveResize else { return }
        hasUserCustomPosition = true
        persistUserCustomSize(self.frame.size)
        self.invalidateShadow()
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard isVisible else { return }
        hasUserCustomPosition = true
        persistUserCustomSize(self.frame.size)
        self.invalidateShadow()
    }

    private func persistUserCustomSize(_ size: NSSize) {
        let clampedWidth = Double(round(max(Self.minWidth, min(size.width, Self.maxWidth))))
        let clampedHeight = Double(round(max(Self.minHeight, min(size.height, Self.maxHeight))))
        var settings = sessionController.storageManager.settings
        if settings.popupWidth != clampedWidth || settings.popupHeight != clampedHeight {
            settings.popupWidth = clampedWidth
            settings.popupHeight = clampedHeight
            sessionController.storageManager.settings = settings
        }
    }

    public func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.dismiss()
            }
            return
        }
        guard !isDismissing, isVisible else { return }
        isDismissing = true
        sessionController.cancelActiveTask()
        removeMonitors()
        self.orderOut(nil)
        isDismissing = false
    }

    private func installMonitors() {
        removeMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self = self, self.isVisible, !self.sessionController.isPinned else { return }
            let clickLoc = NSEvent.mouseLocation
            if !self.frame.contains(clickLoc) {
                self.dismiss()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible, self.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape closes popup (even if pinned)
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            // Cmd + Return -> Auto-Paste translation
            if event.keyCode == 36 && flags == .command {
                self.sessionController.autoPasteTranslationAndDismiss()
                return nil
            }
            // Return -> Copy translation & close
            if event.keyCode == 36 && flags.isEmpty {
                self.sessionController.copyTranslationAndDismiss(shouldDismiss: true)
                return nil
            }
            // Cmd + , -> Preferences
            if flags == .command && event.charactersIgnoringModifiers == "," {
                self.sessionController.onOpenSettings?()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let gm = globalMouseMonitor {
            NSEvent.removeMonitor(gm)
            globalMouseMonitor = nil
        }
        if let lm = localKeyMonitor {
            NSEvent.removeMonitor(lm)
            localKeyMonitor = nil
        }
    }
}
