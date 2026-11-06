import AppKit
import ApplicationServices
import CoreGraphics

public final class SelectionGrabber: @unchecked Sendable {
    public static let shared = SelectionGrabber()

    public init() {}

    /// Attempts to copy currently highlighted text in the frontmost application by posting a synthetic `Cmd + C`.
    /// If the pasteboard changeCount increments within ~130ms, returns the newly copied payload.
    /// Otherwise falls back to whatever payload is already in `NSPasteboard.general`.
    public func grabSelectionOrClipboard(
        pasteboardMonitor: PasteboardMonitor = .shared,
        maxThumbnailPixelSize: Int = 220,
        completion: @escaping (ClipboardPayload?) -> Void
    ) {
        let pasteboard = pasteboardMonitor.pasteboard
        let initialChangeCount = pasteboard.changeCount

        // Only post synthetic Cmd+C if Accessibility is trusted
        guard AXIsProcessTrusted() else {
            let fallback = pasteboardMonitor.extractCurrentPayload(maxThumbnailPixelSize: maxThumbnailPixelSize)
            completion(fallback)
            return
        }

        // Suppress PasteboardMonitor from treating our synthetic copy as an external auto-translate event
        pasteboardMonitor.markSelfCopy(newChangeCount: initialChangeCount + 1)

        postSyntheticCopyKeyEvent()

        // Poll up to 8 times (every 18ms -> ~144ms max) for changeCount update
        pollForPasteboardChange(
            pasteboardMonitor: pasteboardMonitor,
            initialChangeCount: initialChangeCount,
            attemptsRemaining: 8,
            maxThumbnailPixelSize: maxThumbnailPixelSize,
            completion: completion
        )
    }

    private func pollForPasteboardChange(
        pasteboardMonitor: PasteboardMonitor,
        initialChangeCount: Int,
        attemptsRemaining: Int,
        maxThumbnailPixelSize: Int,
        completion: @escaping (ClipboardPayload?) -> Void
    ) {
        let currentCount = pasteboardMonitor.pasteboard.changeCount
        if currentCount != initialChangeCount {
            pasteboardMonitor.markSelfCopy(newChangeCount: currentCount)
            let payload = pasteboardMonitor.extractCurrentPayload(maxThumbnailPixelSize: maxThumbnailPixelSize)
            completion(payload)
            return
        }

        guard attemptsRemaining > 0 else {
            let fallback = pasteboardMonitor.extractCurrentPayload(maxThumbnailPixelSize: maxThumbnailPixelSize)
            completion(fallback)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.018) { [weak self] in
            self?.pollForPasteboardChange(
                pasteboardMonitor: pasteboardMonitor,
                initialChangeCount: initialChangeCount,
                attemptsRemaining: attemptsRemaining - 1,
                maxThumbnailPixelSize: maxThumbnailPixelSize,
                completion: completion
            )
        }
    }

    private func postSyntheticCopyKeyEvent() {
        // Virtual key 0x08 corresponds to kVK_ANSI_C
        let cKeyCode: CGKeyCode = 0x08
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: cKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
