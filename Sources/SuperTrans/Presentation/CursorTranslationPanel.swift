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

/// Floating borderless NSPanel appearing immediately above the mouse cursor when translating.
public final class CursorTranslationPanel: NSPanel {
    public static let defaultWidth: CGFloat = 420
    public let sessionController: TranslationSessionController

    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var anchorMouseLocation: NSPoint = .zero
    private var isDismissing: Bool = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(sessionController: TranslationSessionController) {
        self.sessionController = sessionController
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 180),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        setupPanel()
    }

    private func setupPanel() {
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow

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
        let cursorPoint = mouseLocation ?? NSEvent.mouseLocation
        self.anchorMouseLocation = cursorPoint

        let fittingSize = computeTargetSize()
        let targetFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
            mouseLoc: cursorPoint,
            panelSize: fittingSize
        )

        self.setFrame(targetFrame, display: true)
        self.isDismissing = false
        installMonitors()
        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.invalidateShadow()
    }

    public func recalculateFrameIfVisible() {
        guard isVisible else { return }
        let newSize = computeTargetSize()
        let targetFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
            mouseLoc: anchorMouseLocation,
            panelSize: newSize
        )
        self.setFrame(targetFrame, display: true)
        self.invalidateShadow()
    }

    private func computeTargetSize() -> NSSize {
        let width: CGFloat = Self.defaultWidth
        switch sessionController.state {
        case .idle, .translating:
            return NSSize(width: width, height: 155)
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
