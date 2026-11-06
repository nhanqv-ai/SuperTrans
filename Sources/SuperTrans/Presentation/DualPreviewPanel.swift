import AppKit
import SwiftUI
import SuperTransCore

/// Host view displaying both Original Content (Text or Image Thumbnail) and Full Translated Text on row hover.
public struct DualPreviewHostView: View {
    public let item: TranslationItem?
    public let thumbnailURL: URL?
    @State private var loadedImage: NSImage?

    public init(item: TranslationItem? = nil, thumbnailURL: URL? = nil) {
        self.item = item
        self.thumbnailURL = thumbnailURL
    }

    public var body: some View {
        if let item = item {
            if item.isMasked {
                maskedPreviewCard
            } else {
                unmaskedPreviewCard(for: item)
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private var maskedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("••••••••")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private func unmaskedPreviewCard(for item: TranslationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section 1: Original Content (Image or Text)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: item.contentType == .image ? "photo" : "doc.text")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(LocalizationManager.shared.tr(.originalLabel))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if item.contentType == .image, let w = item.imageWidth, let h = item.imageHeight, w > 0, h > 0 {
                        Text("\(w)x\(h) px")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                if item.contentType == .image {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                        if let img = loadedImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 310, maxHeight: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.secondary)
                                .frame(height: 80)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else if let src = item.sourceText, !src.isEmpty {
                    Text(Self.truncatePreview(src, maxChars: 450))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .opacity(0.5)

            // Section 2: Translated Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("\(LocalizationManager.shared.tr(.translatedLabel)) (\(LanguageOption.option(for: item.targetLanguage).displayName))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.accentColor)
                    Spacer()
                    if let model = item.modelUsed, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }

                Text(Self.truncatePreview(item.translatedText, maxChars: 900))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: thumbnailURL) { _ in
            loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() {
        guard let item = item, item.contentType == .image, !item.isMasked else { return }
        if let url = thumbnailURL, let img = NSImage(contentsOf: url) {
            self.loadedImage = img
        }
    }

    public static func truncatePreview(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxChars {
            return String(trimmed.prefix(maxChars)) + "..."
        }
        return trimmed
    }
}

/// Floating NSPanel displaying dual preview (Original + Translation) when hovering over a history row.
public final class DualPreviewPanel: NSPanel {
    public static let shared = DualPreviewPanel()

    private var hostingView: NSHostingView<DualPreviewHostView>
    private var hideWorkItem: DispatchWorkItem?
    public private(set) var currentItemId: UUID?

    public init() {
        let root = DualPreviewHostView()
        self.hostingView = NSHostingView(rootView: root)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false
        self.contentView = hostingView
    }

    public func show(for item: TranslationItem, thumbnailURL: URL?) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        currentItemId = item.id

        let newView = DualPreviewHostView(item: item, thumbnailURL: thumbnailURL)
        hostingView.rootView = newView
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(width: max(240, min(350, fitting.width)), height: max(80, min(420, fitting.height)))

        let mouseLoc = NSEvent.mouseLocation
        let activeWindowFrame = NSApp.keyWindow?.frame
        let screen = CursorPopupFrameCalculator.findScreen(for: mouseLoc)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var originX: CGFloat
        if let winFrame = activeWindowFrame {
            // Place to the left of the history panel if space allows, otherwise to the right
            if winFrame.minX - size.width - 10 >= visible.minX {
                originX = winFrame.minX - size.width - 10
            } else {
                originX = min(visible.maxX - size.width - 6, winFrame.maxX + 10)
            }
        } else {
            originX = max(visible.minX + 6, mouseLoc.x - size.width - 16)
        }

        var originY = mouseLoc.y - (size.height / 2.0)
        if originY < visible.minY + 6 { originY = visible.minY + 6 }
        if originY + size.height > visible.maxY - 6 { originY = visible.maxY - size.height - 6 }

        self.setFrame(NSRect(x: round(originX), y: round(originY), width: size.width, height: size.height), display: true)
        self.orderFrontRegardless()
    }

    public func hide(immediate: Bool = false) {
        hideWorkItem?.cancel()
        if immediate {
            currentItemId = nil
            self.orderOut(nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.currentItemId = nil
            self?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}
