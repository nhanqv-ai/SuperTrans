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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if case .completed = controller.state {
                Divider().opacity(0.55)
                footerBar
            }
        }
        .frame(
            minWidth: CursorTranslationPanel.minWidth,
            maxWidth: .infinity,
            minHeight: CursorTranslationPanel.minHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
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
        .ignoresSafeArea()
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            SuperTransBrandIcon(size: 16)

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

            // Project Switcher Menu
            Menu {
                ForEach(controller.storageManager.projects) { project in
                    Button(action: {
                        if controller.storageManager.activeProject.id != project.id {
                            controller.selectProjectAndRetranslate(project.id)
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text(project.name)
                            if controller.storageManager.activeProject.id == project.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(action: {
                    controller.onDismissPopup?()
                    controller.onOpenSettings?()
                }) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text(loc.languageCode == "vi" ? "Quản lý Dự án & Từ điển..." : "Manage Projects & Glossary...")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(controller.storageManager.activeProject.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(loc.languageCode == "vi" ? "Chọn Dự án (tách biệt bộ nhớ học & thuật ngữ)" : "Select Project (isolated learning memory & glossary)")

            Spacer()

            if controller.didLearnFeedback {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text(loc.languageCode == "vi" ? "Đã dạy AI" : "Learned")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.14)))
            }

            // Edit / Teach AI Button
            if case .completed = controller.state {
                Button(action: {
                    controller.toggleEditAndTeachMode()
                }) {
                    Image(systemName: controller.isEditingTranslation ? "pencil.circle.fill" : "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(controller.isEditingTranslation ? .accentColor : .secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc.languageCode == "vi" ? "Sửa bản dịch & Dạy thuật ngữ cho Project này" : "Edit translation & teach glossary for this Project")
            }

            // Toggle Original Content Preview
            if controller.payload != nil {
                Button(action: {
                    controller.showOriginalContent.toggle()
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
        let isVi = loc.languageCode == "vi"
        return VStack(alignment: .leading, spacing: 8) {
            if controller.showOriginalContent, let payload = controller.payload {
                sourceExpandedPreview(payload: payload)
                Divider().opacity(0.4)
            }

            if controller.isEditingTranslation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text(isVi
                             ? "Sửa bản dịch chuẩn (Dạy câu mẫu cho Project \"\(controller.storageManager.activeProject.name)\"):"
                             : "Edit Gold Translation (Teach example for Project \"\(controller.storageManager.activeProject.name)\"):")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    TextEditor(text: $controller.editedTranslationDraft)
                        .font(.system(size: 12.5))
                        .frame(minHeight: 70, maxHeight: .infinity)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isVi ? "Ghim nhanh Thuật ngữ vào Từ điển Project (Tuỳ chọn):" : "Quick-add Term to Project Glossary (Optional):")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            TextField(isVi ? "Từ gốc (VD: 代表)" : "Source term", text: $controller.quickGlossarySourceDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            TextField(isVi ? "Nghĩa chuẩn (VD: tổng đài)" : "Target term", text: $controller.quickGlossaryTargetDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                        }
                    }

                    HStack(spacing: 8) {
                        Spacer()
                        Button(action: {
                            controller.toggleEditAndTeachMode()
                        }) {
                            Text(isVi ? "Huỷ" : "Cancel")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.14)))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            controller.saveEditedTranslationAndGlossary()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                Text(isVi ? "Lưu & Dạy AI" : "Save & Teach AI")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(translatedText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, minHeight: 54, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var currentPromptShortTitle: String {
        let isVi = loc.languageCode == "vi"
        let currentPrompt = controller.storageManager.settings.customSystemPrompt
        if let matched = AppSettings.matchingPromptPreset(for: currentPrompt) {
            return isVi ? matched.shortTitleVi : matched.shortTitleEn
        }
        return isVi ? "Prompt tuỳ chỉnh" : "Custom Prompt"
    }

    private var footerBar: some View {
        let isVi = loc.languageCode == "vi"
        let currentMatchedId = AppSettings.matchingPromptPreset(for: controller.storageManager.settings.customSystemPrompt)?.id

        return HStack(spacing: 8) {
            // Quick Prompt Style Dropdown (Select & immediately re-translate)
            Menu {
                ForEach(AppSettings.promptPresets) { preset in
                    Button(action: {
                        controller.selectPromptPresetAndRetranslate(preset.prompt)
                    }) {
                        HStack {
                            Text(isVi ? preset.titleVi : preset.titleEn)
                            if currentMatchedId == preset.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(currentPromptShortTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.14)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isVi ? "Chọn kiểu Prompt và dịch lại ngay" : "Select Prompt style and re-translate immediately")

            Spacer()

            // Re-translate button
            Button(action: {
                controller.retranslate()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text(loc.tr(.popupRetranslate))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.14)))
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
                        .lineLimit(1)
                }
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
