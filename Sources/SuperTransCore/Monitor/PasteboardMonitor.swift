import AppKit
import CoreGraphics
import ImageIO

public enum ClipboardPayload: Equatable, Sendable {
    case text(String)
    case image(pngData: Data, thumbData: Data, width: Int, height: Int)
}

public protocol PasteboardMonitoring: AnyObject {
    var onCopyDetected: ((ClipboardPayload, Bool) -> Void)? { get set }
    func startPolling(intervalMs: Int)
    func stopPolling()
    func markSelfCopy(newChangeCount: Int)
    func extractCurrentPayload(maxThumbnailPixelSize: Int) -> ClipboardPayload?
}

public final class PasteboardMonitor: PasteboardMonitoring, @unchecked Sendable {
    public static let shared = PasteboardMonitor()

    public let pasteboard: NSPasteboard
    private let monitorQueue = DispatchQueue(label: "com.nhanqv.supertrans.pasteboard.monitor", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var globalKeyMonitor: Any?
    private var isPolling = false
    private let stateLock = NSLock()

    public var lastChangeCount: Int
    private var suppressedChangeCounts: Set<Int> = []
    private var lastCopyTimestamp: TimeInterval = 0
    private var lastCmdCKeyTimestamp: TimeInterval = 0
    public var doubleCopyWindowSeconds: TimeInterval = 0.45
    public var maxThumbnailPixelSize: Int = 220

    public var isIgnoredAppCheck: ((_ bundleIdentifier: String?, _ name: String?) -> Bool)?

    /// Callback invoked when clipboard changes or double-copy occurs:
    /// `(payload, isDoubleCopy)`
    public var onCopyDetected: ((ClipboardPayload, Bool) -> Void)?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    public func startPolling(intervalMs: Int = 180) {
        stateLock.lock()
        if isPolling {
            timer?.cancel()
            timer = nil
        }

        let t = DispatchSource.makeTimerSource(queue: monitorQueue)
        t.schedule(
            deadline: .now(),
            repeating: .milliseconds(max(50, intervalMs)),
            leeway: .milliseconds(30)
        )
        t.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        timer = t
        isPolling = true
        t.resume()
        stateLock.unlock()

        installGlobalKeyMonitorIfNeeded()
    }

    public func stopPolling() {
        stateLock.lock()
        if isPolling {
            timer?.cancel()
            timer = nil
            isPolling = false
        }
        stateLock.unlock()

        if Thread.isMainThread {
            if let monitor = globalKeyMonitor {
                NSEvent.removeMonitor(monitor)
                globalKeyMonitor = nil
            }
        } else {
            DispatchQueue.main.sync {
                if let monitor = globalKeyMonitor {
                    NSEvent.removeMonitor(monitor)
                    globalKeyMonitor = nil
                }
            }
        }
    }

    private func installGlobalKeyMonitorIfNeeded() {
        let installBlock = { [weak self] in
            guard let self = self, self.globalKeyMonitor == nil else { return }
            self.globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleGlobalKeyDown(event)
            }
        }
        if Thread.isMainThread {
            installBlock()
        } else {
            DispatchQueue.main.async(execute: installBlock)
        }
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        // Virtual key 8 is kVK_ANSI_C
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command && event.keyCode == 8 && !event.isARepeat else { return }

        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let delta = now - lastCmdCKeyTimestamp
        lastCmdCKeyTimestamp = now
        let isDouble = delta > 0.04 && delta <= doubleCopyWindowSeconds
        stateLock.unlock()

        if isDouble {
            // Wait briefly for the second Cmd+C to settle in NSPasteboard, then emit double copy
            monitorQueue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self = self else { return }
                guard !self.isFrontmostAppIgnored() else { return }
                self.stateLock.lock()
                self.lastChangeCount = self.pasteboard.changeCount
                self.lastCopyTimestamp = 0 // Prevent duplicate trigger from poll loop
                self.stateLock.unlock()

                if let payload = self.extractCurrentPayload(maxThumbnailPixelSize: self.maxThumbnailPixelSize) {
                    self.onCopyDetected?(payload, true)
                }
            }
        }
    }

    public func markSelfCopy(newChangeCount: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        suppressedChangeCounts.insert(newChangeCount)
        lastChangeCount = newChangeCount
    }

    public func isFrontmostAppIgnored() -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleId = app?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = app?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return isIgnoredAppCheck?(bundleId, name) ?? false
    }

    private func checkPasteboard() {
        autoreleasepool {
            let currentCount = pasteboard.changeCount
            let now = ProcessInfo.processInfo.systemUptime

            stateLock.lock()
            if suppressedChangeCounts.contains(currentCount) {
                suppressedChangeCounts = suppressedChangeCounts.filter { $0 > currentCount }
                lastChangeCount = currentCount
                stateLock.unlock()
                return
            }

            suppressedChangeCounts = suppressedChangeCounts.filter { $0 > currentCount }
            guard currentCount != lastChangeCount else {
                stateLock.unlock()
                return
            }

            lastChangeCount = currentCount
            let delta = now - lastCopyTimestamp
            let isDoubleCopy = delta > 0.03 && delta <= doubleCopyWindowSeconds
            lastCopyTimestamp = isDoubleCopy ? 0 : now
            stateLock.unlock()

            guard !isFrontmostAppIgnored() else { return }

            if let payload = extractCurrentPayload(maxThumbnailPixelSize: maxThumbnailPixelSize) {
                onCopyDetected?(payload, isDoubleCopy)
            }
        }
    }

    public func extractCurrentPayload(maxThumbnailPixelSize: Int = 220) -> ClipboardPayload? {
        // 1. Check PNG image data
        if let pngData = pasteboard.data(forType: .png),
           let (thumbData, width, height) = ThumbnailGenerator.generateThumbnail(from: pngData, maxPixelSize: maxThumbnailPixelSize) {
            return .image(pngData: pngData, thumbData: thumbData, width: width, height: height)
        }

        // 2. Check TIFF image data
        if let tiffData = pasteboard.data(forType: .tiff),
           let normalizedPNG = ThumbnailGenerator.normalizedPNGData(from: tiffData),
           let (thumbData, width, height) = ThumbnailGenerator.generateThumbnail(from: normalizedPNG, maxPixelSize: maxThumbnailPixelSize) {
            return .image(pngData: normalizedPNG, thumbData: thumbData, width: width, height: height)
        }

        // 3. Check if an image file URL was copied in Finder (.png, .jpg, .jpeg, .webp, .heic)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first,
           firstURL.isFileURL {
            let ext = firstURL.pathExtension.lowercased()
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "bmp"]
            if imageExts.contains(ext),
               let fileData = try? Data(contentsOf: firstURL),
               let normalizedPNG = ThumbnailGenerator.normalizedPNGData(from: fileData),
               let (thumbData, width, height) = ThumbnailGenerator.generateThumbnail(from: normalizedPNG, maxPixelSize: maxThumbnailPixelSize) {
                return .image(pngData: normalizedPNG, thumbData: thumbData, width: width, height: height)
            }
        }

        // 4. Check plain text string
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .text(trimmed)
            }
        }

        return nil
    }
}
