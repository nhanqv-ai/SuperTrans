import SwiftUI
import AppKit
import SuperTransCore

public struct WindowAccessor: NSViewRepresentable {
    public var callback: (NSWindow?) -> Void

    public init(callback: @escaping (NSWindow?) -> Void) {
        self.callback = callback
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.callback(nsView.window)
        }
    }
}

public struct MainHistoryView: View {
    @ObservedObject public var storageManager: StorageManager
    @ObservedObject public var updateManager: UpdateManager = .shared
    @ObservedObject private var loc = LocalizationManager.shared

    public let pasteboardWriter: any PasteboardWriting
    public let autoPasteService: any AutoPasteServicing
    public let previousAppTracker: any PreviousAppTracking

    public var onDismiss: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onTranslateClipboardNow: (() -> Void)?
    public var onOpenItemInPopup: ((TranslationItem) -> Void)?
    public var onRetranslateItem: ((TranslationItem) -> Void)?

    @State private var searchText: String = ""
    @State private var selectedIndex: Int? = nil
    @State private var localKeyMonitor: Any? = nil
    @State private var hostWindow: NSWindow? = nil
    @State private var showAllProjectsInHistory: Bool = false

    public init(
        storageManager: StorageManager,
        pasteboardWriter: any PasteboardWriting,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared,
        onDismiss: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onTranslateClipboardNow: (() -> Void)? = nil,
        onOpenItemInPopup: ((TranslationItem) -> Void)? = nil,
        onRetranslateItem: ((TranslationItem) -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.pasteboardWriter = pasteboardWriter
        self.autoPasteService = autoPasteService
        self.previousAppTracker = previousAppTracker
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onTranslateClipboardNow = onTranslateClipboardNow
        self.onOpenItemInPopup = onOpenItemInPopup
        self.onRetranslateItem = onRetranslateItem
    }

    public var partitionedItems: (pinned: [TranslationItem], recent: [TranslationItem]) {
        let activeProjId = storageManager.activeProject.id
        let baseItems = showAllProjectsInHistory
            ? storageManager.items
            : storageManager.items.filter { $0.projectId == activeProjId }
        let (pinned, recent) = SearchEngine.partition(items: baseItems, query: searchText)
        let maxDisplay = storageManager.settings.displayCapacity
        let cappedRecent = maxDisplay > 0 ? Array(recent.prefix(maxDisplay)) : recent
        return (pinned: pinned, recent: cappedRecent)
    }

    public var visibleItems: [TranslationItem] {
        partitionedItems.pinned + partitionedItems.recent
    }

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                headerBar
                projectSelectorBar
                searchBarSection
                if updateManager.shouldShowBanner {
                    updateBannerView
                }
                Divider().opacity(0.6)
                contentSection
            }
            .frame(width: 390, height: 600)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                WindowAccessor { win in
                    if let win = win {
                        self.hostWindow = win
                    }
                }
            )
            .onAppear {
                installKeyboardMonitor()
                resetSelection(scrollProxy: proxy)
            }
            .onDisappear {
                DualPreviewPanel.shared.hide(immediate: true)
                removeKeyboardMonitor()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
                guard let win = notif.object as? NSWindow else { return }
                if let host = hostWindow, win === host {
                    installKeyboardMonitor()
                    resetSelection(scrollProxy: proxy)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notif in
                guard let win = notif.object as? NSWindow else { return }
                if let host = hostWindow, win === host {
                    removeKeyboardMonitor()
                }
            }
            .onChange(of: searchText) { newQuery in
                resetSelection(query: newQuery, scrollProxy: proxy)
            }
            .onChange(of: storageManager.items) { _ in
                resetSelection(scrollProxy: proxy)
            }
            .onChange(of: selectedIndex) { newIdx in
                if let idx = newIdx, idx >= 0 && idx < visibleItems.count {
                    let targetID = visibleItems[idx].id
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            Text("SuperTrans")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            // Quick Target Language Menu
            Menu {
                ForEach(LanguageOption.supported) { option in
                    Button(action: {
                        var s = storageManager.settings
                        s.targetLanguage = option.code
                        storageManager.settings = s
                    }) {
                        HStack {
                            Text(option.displayName)
                            if storageManager.settings.targetLanguage == option.code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(LanguageOption.option(for: storageManager.settings.targetLanguage).displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Quick Auto-Translate Toggle Button
            Button(action: {
                var s = storageManager.settings
                s.autoTranslateEveryCopy.toggle()
                storageManager.settings = s
            }) {
                HStack(spacing: 3) {
                    Image(systemName: storageManager.settings.autoTranslateEveryCopy ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Auto")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(storageManager.settings.autoTranslateEveryCopy ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundColor(storageManager.settings.autoTranslateEveryCopy ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help(loc.tr(.autoTranslateOnCopy))

            // Translate Clipboard Now Button
            Button(action: {
                onDismiss?()
                onTranslateClipboardNow?()
            }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.tr(.translateClipboardNow))

            // Settings Button
            Button(action: {
                onOpenSettings?()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)

                    if updateManager.hasPendingUpdate {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.tr(.preferencesTooltip))

            // Dismiss Button
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.tr(.dismissTooltip))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var projectSelectorBar: some View {
        let isVi = loc.languageCode == "vi"
        let activeProject = storageManager.activeProject
        let verifiedOrPinnedCount = storageManager.items.filter {
            $0.projectId == activeProject.id && ($0.isVerified || $0.isPinned)
        }.count
        let glossaryCount = activeProject.glossary.count

        return HStack(spacing: 6) {
            Menu {
                ForEach(storageManager.projects) { project in
                    Button(action: {
                        storageManager.selectActiveProject(id: project.id)
                    }) {
                        HStack {
                            Text("📁 \(project.name)")
                            if activeProject.id == project.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(action: {
                    onOpenSettings?()
                }) {
                    Text(isVi ? "⚙️ Quản lý Dự án & Từ điển..." : "⚙️ Manage Projects & Glossary...")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(activeProject.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(isVi
                 ? "\(glossaryCount) thuật ngữ · \(verifiedOrPinnedCount) câu mẫu"
                 : "\(glossaryCount) terms · \(verifiedOrPinnedCount) examples")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                showAllProjectsInHistory.toggle()
            }) {
                Text(showAllProjectsInHistory
                     ? (isVi ? "Tất cả dự án" : "All projects")
                     : (isVi ? "Chỉ dự án này" : "This project"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(showAllProjectsInHistory ? .accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(showAllProjectsInHistory ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help(isVi ? "Bật/tắt lọc lịch sử theo dự án đang chọn" : "Toggle filtering history by active project")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        SearchBarView(
            text: $searchText,
            placeholder: loc.tr(.searchPlaceholder),
            onCommit: {
                handleReturnKey()
            }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Update Banner View

    public var updateBannerView: some View {
        let isVi = loc.languageCode == "vi"
        return HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1) {
                switch updateManager.status {
                case .readyToRestart:
                    Text(isVi ? "Bản cập nhật đã sẵn sàng khởi động lại" : "Update ready to restart")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                case .downloading:
                    Text(isVi ? "Đang tải bản cập nhật..." : "Downloading update...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                case .updateAvailable(let release):
                    let tag = release.tagName.lowercased().hasPrefix("v") ? release.tagName : "v\(release.tagName)"
                    Text(isVi ? "Đã có bản cập nhật \(tag)" : "Update \(tag) available")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                case .error(let msg):
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .lineLimit(1)
                default:
                    EmptyView()
                }
            }

            Spacer()

            switch updateManager.status {
            case .readyToRestart:
                Button(action: { updateManager.dismissBannerForSession() }) {
                    Text(isVi ? "Để sau" : "Later")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: { updateManager.restartApp() }) {
                    Text(isVi ? "Khởi động lại" : "Restart")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)

            case .updateAvailable(let release):
                Button(action: { NSWorkspace.shared.open(release.htmlURL) }) {
                    Text(isVi ? "Chi tiết" : "Notes")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: { updateManager.dismissBannerForSession() }) {
                    Text(isVi ? "Để sau" : "Later")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: { updateManager.startDownloadAndInstall(release: release) }) {
                    Text(isVi ? "Cập nhật" : "Update")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .error:
                Button(action: { updateManager.dismissBannerForSession() }) {
                    Text(isVi ? "Đóng" : "Dismiss")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
    }

    // MARK: - Content List Section

    @ViewBuilder
    private var contentSection: some View {
        if visibleItems.isEmpty {
            emptyStateView
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let (pinned, recent) = partitionedItems

                    if !pinned.isEmpty {
                        sectionHeader(title: loc.tr(.pinnedSection), count: pinned.count)
                        ForEach(Array(pinned.enumerated()), id: \.element.id) { idx, item in
                            let globalIndex = idx
                            rowView(for: item, globalIndex: globalIndex)
                                .id(item.id)
                        }
                    }

                    if !recent.isEmpty {
                        sectionHeader(title: loc.tr(.recentSection), count: recent.count)
                        ForEach(Array(recent.enumerated()), id: \.element.id) { idx, item in
                            let globalIndex = pinned.count + idx
                            rowView(for: item, globalIndex: globalIndex)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func rowView(for item: TranslationItem, globalIndex: Int) -> some View {
        let isSelected = (selectedIndex == globalIndex)
        return HistoryRowView(
            item: item,
            thumbnailURL: storageManager.getThumbnailURL(for: item),
            isSelected: isSelected,
            onSelect: { selected in
                selectAndPasteItem(selected)
            },
            onCopyOriginal: { selected in
                _ = pasteboardWriter.writeOriginal(selected, storageManager: storageManager)
                onDismiss?()
            },
            onOpenInPopup: { selected in
                onDismiss?()
                onOpenItemInPopup?(selected)
            },
            onRetranslate: { selected in
                onDismiss?()
                onRetranslateItem?(selected)
            },
            onTogglePin: { selected in
                storageManager.togglePin(id: selected.id)
            },
            onToggleMask: { selected in
                storageManager.toggleMaskItem(id: selected.id)
            },
            onDelete: { selected in
                storageManager.deleteItem(id: selected.id)
            }
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : "character.bubble")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))

            Text(isSearching ? loc.tr(.noSearchResultsTitle) : loc.tr(.emptyHistoryTitle))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Text(isSearching ? loc.tr(.noSearchResultsSubtitle) : loc.tr(.emptyHistorySubtitle))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection & Keyboard Handling

    private func selectAndPasteItem(_ item: TranslationItem) {
        DualPreviewPanel.shared.hide(immediate: true)
        _ = pasteboardWriter.writeTranslation(item)
        let targetApp = previousAppTracker.previousApp
        onDismiss?()

        if storageManager.settings.autoPasteOnSelection && autoPasteService.isAccessibilityTrusted {
            _ = autoPasteService.pasteToActiveApp(targetApp: targetApp, delay: 0.04, completion: nil)
        }
    }

    private func resetSelection(query: String? = nil, scrollProxy: ScrollViewProxy? = nil) {
        let q = query ?? searchText
        let (pinned, recent) = SearchEngine.partition(items: storageManager.items, query: q)
        let maxDisplay = storageManager.settings.displayCapacity
        let cappedRecent = maxDisplay > 0 ? Array(recent.prefix(maxDisplay)) : recent
        let all = pinned + cappedRecent
        if all.isEmpty {
            selectedIndex = nil
        } else {
            selectedIndex = 0
            if let firstId = all.first?.id {
                scrollProxy?.scrollTo(firstId, anchor: .top)
            }
        }
    }

    private func handleReturnKey() {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let idx = selectedIndex ?? 0
        guard idx >= 0 && idx < items.count else { return }
        selectAndPasteItem(items[idx])
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape
            if event.keyCode == 53 {
                DualPreviewPanel.shared.hide(immediate: true)
                onDismiss?()
                return nil
            }
            // Up Arrow (126)
            if event.keyCode == 126 {
                selectedIndex = ShortcutNavigator.moveUp(currentIndex: selectedIndex, totalCount: visibleItems.count)
                return nil
            }
            // Down Arrow (125)
            if event.keyCode == 125 {
                selectedIndex = ShortcutNavigator.moveDown(currentIndex: selectedIndex, totalCount: visibleItems.count)
                return nil
            }
            // Return / Enter (36 or 76)
            if event.keyCode == 36 || event.keyCode == 76 {
                handleReturnKey()
                return nil
            }
            // Cmd + , -> Preferences
            if flags == .command && event.charactersIgnoringModifiers == "," {
                onOpenSettings?()
                return nil
            }
            // Cmd + Q -> Quit
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
