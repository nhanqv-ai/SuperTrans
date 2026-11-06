import AppKit
import SwiftUI
import SuperTransCore

public struct HistoryRowView: View {
    public let item: TranslationItem
    public let shortcutIndex: Int?
    public let thumbnailURL: URL?
    public let isSelected: Bool
    public var onSelect: ((TranslationItem) -> Void)?
    public var onCopyOriginal: ((TranslationItem) -> Void)?
    public var onOpenInPopup: ((TranslationItem) -> Void)?
    public var onRetranslate: ((TranslationItem) -> Void)?
    public var onTogglePin: ((TranslationItem) -> Void)?
    public var onToggleMask: ((TranslationItem) -> Void)?
    public var onDelete: ((TranslationItem) -> Void)?

    @State private var isHovered: Bool = false
    @ObservedObject private var loc = LocalizationManager.shared

    public init(
        item: TranslationItem,
        shortcutIndex: Int? = nil,
        thumbnailURL: URL? = nil,
        isSelected: Bool = false,
        onSelect: ((TranslationItem) -> Void)? = nil,
        onCopyOriginal: ((TranslationItem) -> Void)? = nil,
        onOpenInPopup: ((TranslationItem) -> Void)? = nil,
        onRetranslate: ((TranslationItem) -> Void)? = nil,
        onTogglePin: ((TranslationItem) -> Void)? = nil,
        onToggleMask: ((TranslationItem) -> Void)? = nil,
        onDelete: ((TranslationItem) -> Void)? = nil
    ) {
        self.item = item
        self.shortcutIndex = shortcutIndex
        self.thumbnailURL = thumbnailURL
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onCopyOriginal = onCopyOriginal
        self.onOpenInPopup = onOpenInPopup
        self.onRetranslate = onRetranslate
        self.onTogglePin = onTogglePin
        self.onToggleMask = onToggleMask
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Left type/language indicator
            leadingBadge

            // Main single-line translated text button
            Button(action: {
                DualPreviewPanel.shared.hide(immediate: true)
                onSelect?(item)
            }) {
                Text(rowDisplayText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Trailing hover actions & shortcut badge
            trailingControls
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(backgroundFillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(borderStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
            if hovering {
                DualPreviewPanel.shared.show(for: item, thumbnailURL: thumbnailURL)
            } else {
                DualPreviewPanel.shared.hide()
            }
        }
        .contextMenu {
            Button(loc.tr(.copyTranslation)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onSelect?(item)
            }
            Button(loc.tr(.copyOriginal)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onCopyOriginal?(item)
            }
            Button(loc.tr(.openInPopup)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onOpenInPopup?(item)
            }
            Button(loc.tr(.retranslateItem)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onRetranslate?(item)
            }
            Divider()
            Button(item.isPinned ? loc.tr(.unpinItem) : loc.tr(.pinItem)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onTogglePin?(item)
            }
            Button(item.isMasked ? loc.tr(.revealItem) : loc.tr(.maskItem)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onToggleMask?(item)
            }
            Divider()
            Button(loc.tr(.deleteItem)) {
                DualPreviewPanel.shared.hide(immediate: true)
                onDelete?(item)
            }
        }
    }

    private var leadingBadge: some View {
        HStack(spacing: 3) {
            if item.contentType == .image {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            Text(item.targetLanguage.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
        }
    }

    private var rowDisplayText: String {
        if item.isMasked {
            return "••••••••"
        }
        let oneLine = item.translatedText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !oneLine.isEmpty {
            return oneLine
        }
        return item.displayTitle
    }

    private var trailingControls: some View {
        HStack(spacing: 4) {
            if isHovered {
                Button(action: {
                    DualPreviewPanel.shared.hide(immediate: true)
                    onOpenInPopup?(item)
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc.tr(.openInPopup))

                Button(action: {
                    DualPreviewPanel.shared.hide(immediate: true)
                    onToggleMask?(item)
                }) {
                    Image(systemName: item.isMasked ? "eye" : "eye.slash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(item.isMasked ? .accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isMasked ? loc.tr(.revealItem) : loc.tr(.maskItem))

                Button(action: {
                    DualPreviewPanel.shared.hide(immediate: true)
                    onTogglePin?(item)
                }) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(item.isPinned ? .accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? loc.tr(.unpinItem) : loc.tr(.pinItem))

                Button(action: {
                    DualPreviewPanel.shared.hide(immediate: true)
                    onDelete?(item)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc.tr(.deleteItem))
            } else {
                if item.isMasked {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)
                }
            }

            if let idx = shortcutIndex, (1...9).contains(idx) {
                Text("\(idx)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(isSelected ? 0.24 : 0.12))
                    )
            }
        }
    }

    private var backgroundFillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        } else if isHovered {
            return Color.primary.opacity(0.07)
        }
        return Color.clear
    }

    private var borderStrokeColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        return Color.clear
    }
}
