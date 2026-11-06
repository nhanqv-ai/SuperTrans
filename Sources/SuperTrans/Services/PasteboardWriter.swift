import AppKit
import SuperTransCore

public protocol PasteboardWriting: AnyObject {
    @discardableResult
    func writeText(_ text: String) -> Bool
    @discardableResult
    func writeTranslation(_ item: TranslationItem) -> Bool
    @discardableResult
    func writeOriginal(_ item: TranslationItem, storageManager: StorageManager) -> Bool
}

public final class PasteboardWriter: PasteboardWriting, @unchecked Sendable {
    public let pasteboard: NSPasteboard
    public weak var monitor: (any PasteboardMonitoring)?

    public init(pasteboard: NSPasteboard = .general, monitor: (any PasteboardMonitoring)? = PasteboardMonitor.shared) {
        self.pasteboard = pasteboard
        self.monitor = monitor
    }

    @discardableResult
    public func writeText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        monitor?.markSelfCopy(newChangeCount: pasteboard.changeCount)
        return ok
    }

    @discardableResult
    public func writeTranslation(_ item: TranslationItem) -> Bool {
        return writeText(item.translatedText)
    }

    @discardableResult
    public func writeOriginal(_ item: TranslationItem, storageManager: StorageManager) -> Bool {
        switch item.contentType {
        case .text:
            if let src = item.sourceText, !src.isEmpty {
                return writeText(src)
            }
            return writeText(item.translatedText)
        case .image:
            if let imgData = storageManager.getImageData(for: item) {
                pasteboard.clearContents()
                let ok = pasteboard.setData(imgData, forType: .png)
                monitor?.markSelfCopy(newChangeCount: pasteboard.changeCount)
                return ok
            }
            return false
        }
    }
}
