import AppKit
import SwiftUI
import SuperTransCore

public protocol FloatingPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    var isKeyWindow: Bool { get }
    func show(near mouseLocation: NSPoint)
    func dismiss()
}

public final class FloatingHistoryPanel: NSPanel, FloatingPanelPresenting {
    public static let defaultPanelSize = NSSize(width: 390, height: 600)

    public var onDismiss: (() -> Void)?
    public var previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isDismissing: Bool = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(contentRect: NSRect = NSRect(origin: .zero, size: defaultPanelSize)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setupPanelAttributes()
        setupNotificationObservers()
    }

    public convenience init<V: View>(size: NSSize = defaultPanelSize, rootView: V) {
        self.init(contentRect: NSRect(origin: .zero, size: size))
        setRootView(rootView)
    }

    private func setupPanelAttributes() {
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    public func setRootView<V: View>(_ view: V) {
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentViewController = hostingController
        self.invalidateShadow()
    }

    public func present(at frame: NSRect) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.present(at: frame)
            }
            return
        }

        previousAppTracker.captureFrontmostApplication()
        self.setFrame(frame, display: true)
        self.isDismissing = false
        installEventMonitors()
        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.invalidateShadow()
    }

    public func show(near mouseLocation: NSPoint) {
        let targetFrame = CursorPopupFrameCalculator.calculateClampedHistoryPanelFrame(
            mouseLoc: mouseLocation,
            panelSize: self.frame.size
        )
        present(at: targetFrame)
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
        removeEventMonitors()
        DualPreviewPanel.shared.hide(immediate: true)
        self.orderOut(nil)
        isDismissing = false
        onDismiss?()
    }

    public override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    @objc private func handleWindowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            let clickLoc = NSEvent.mouseLocation
            if !self.frame.contains(clickLoc) {
                self.dismiss()
            }
        }
    }

    private func removeEventMonitors() {
        if let gm = globalMouseMonitor {
            NSEvent.removeMonitor(gm)
            globalMouseMonitor = nil
        }
        if let lm = localMouseMonitor {
            NSEvent.removeMonitor(lm)
            localMouseMonitor = nil
        }
    }

    deinit {
        removeEventMonitors()
        NotificationCenter.default.removeObserver(self)
    }
}
