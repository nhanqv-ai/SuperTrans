import SwiftUI
import AppKit
import SuperTransCore

public struct CursorPopupView: View {
    @ObservedObject public var controller: TranslationSessionController
    @ObservedObject private var loc = LocalizationManager.shared

    public init(controller: TranslationSessionController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().opacity(0.55)
            contentArea
            if case .completed = controller.state {
                Divider().opacity(0.55)
                footerBar
            }
        }
        .frame(width: CursorTranslationPanel.defaultWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)

            // Target Language Picker Menu
            Menu {
                ForEach(LanguageOption.supported) { option in
                    Button(action: {
                        if controller.targetLanguage != option.code {
                            controller.retranslate(newTargetLanguage: option.code)
                        }
                    }) {
                        HStack {
                            Text(option.displayName)
                            if controller.targetLanguage == option.code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(loc.tr(.popupTargetLanguage)): \(LanguageOption.option(for: controller.targetLanguage).displayName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Toggle Original Content Preview
            if controller.payload != nil {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        controller.showOriginalContent.toggle()
                    }
                    controller.onContentSizeChanged?()
                }) {
                    Image(systemName: controller.showOriginalContent ? "doc.text.fill" : "doc.text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(controller.showOriginalContent ? .accentColor : .secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(controller.showOriginalContent ? loc.tr(.popupHideOriginal) : loc.tr(.popupShowOriginal))
            }

            // Pin Popup Button
            Button(action: {
                controller.isPinned.toggle()
            }) {
                Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(controller.isPinned ? .accentColor : .secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.tr(.popupPinTooltip))

            // Close Button
            Button(action: {
                controller.onDismissPopup?()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.tr(.popupCloseTooltip))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch controller.state {
        case .idle, .translating:
            translatingView
        case .failed(let message, let isMissingKey):
            failedView(message: message, isMissingKey: isMissingKey)
        case .completed(let translatedText, _, _):
            completedView(translatedText: translatedText)
        }
    }

    private var translatingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(loc.tr(.popupTranslating))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }

            if let payload = controller.payload {
                sourceCompactPreview(payload: payload)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failedView(message: String, isMissingKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if isMissingKey {
                    Button(action: {
                        controller.onDismissPopup?()
                        controller.onOpenSettings?()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                            Text(loc.tr(.popupConfigureAPIKey))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    controller.retranslate()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text(loc.tr(.popupRetry))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
    }

    private func completedView(translatedText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.showOriginalContent, let payload = controller.payload {
                sourceExpandedPreview(payload: payload)
                Divider().opacity(0.4)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(translatedText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(minHeight: 54, maxHeight: 280)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func sourceCompactPreview(payload: ClipboardPayload) -> some View {
        switch payload {
        case .text(let src):
            Text(src.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        case .image(_, let thumbData, let width, let height):
            HStack(spacing: 8) {
                if let nsImg = NSImage(data: thumbData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text("\(loc.tr(.imageTag)) \(width)x\(height) px")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }

    @ViewBuilder
    private func sourceExpandedPreview(payload: ClipboardPayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.tr(.originalLabel))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)

            switch payload {
            case .text(let src):
                ScrollView(.vertical, showsIndicators: true) {
                    Text(src)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            case .image(_, let thumbData, let width, let height):
                HStack(spacing: 10) {
                    if let nsImg = NSImage(data: thumbData) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 140, maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text("\(width) x \(height) px")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 6) {
            if case .completed(_, let modelUsed, _) = controller.state {
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                    Text(modelUsed)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Re-translate button
            Button(action: {
                controller.retranslate()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text(loc.tr(.popupRetranslate))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            // Auto-Paste button (Cmd + Enter)
            Button(action: {
                controller.autoPasteTranslationAndDismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text(loc.tr(.popupAutoPaste))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            // Copy button (Enter)
            Button(action: {
                controller.copyTranslationAndDismiss(shouldDismiss: !controller.isPinned)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: controller.didCopyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(controller.didCopyFeedback ? loc.tr(.popupCopied) : loc.tr(.popupCopyTranslation))
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
