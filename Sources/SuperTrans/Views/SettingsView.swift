import SwiftUI
import AppKit
import Carbon
import UniformTypeIdentifiers
import SuperTransCore

public struct SettingsView: View {
    @ObservedObject public var storageManager: StorageManager
    @ObservedObject public var updateManager: UpdateManager = .shared
    @ObservedObject private var loc = LocalizationManager.shared
    public let hotKeyManager: any HotKeyManaging
    public let autoPasteService: any AutoPasteServicing
    public var onDismiss: (() -> Void)?

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case geminiAI
        case prompt
        case projects
        case ignoredApps
        case about

        public var id: String { rawValue }

        public var title: String {
            let isVi = LocalizationManager.shared.languageCode == "vi"
            switch self {
            case .general: return LocalizationManager.shared.tr(.tabGeneral)
            case .geminiAI: return LocalizationManager.shared.tr(.tabGeminiAI)
            case .prompt: return "Prompt"
            case .projects: return isVi ? "Dự án" : "Projects"
            case .ignoredApps: return LocalizationManager.shared.tr(.tabIgnoredApps)
            case .about: return isVi ? "Thông tin" : "About"
            }
        }

        public var iconName: String {
            switch self {
            case .general: return "gear"
            case .geminiAI: return "sparkles"
            case .prompt: return "text.bubble"
            case .projects: return "folder.badge.gearshape"
            case .ignoredApps: return "eye.slash"
            case .about: return "info.circle"
            }
        }
    }

    @AppStorage("SuperTrans.lastSelectedSettingsTab") private var selectedTabRaw: String = SettingsTab.general.rawValue

    private var selectedTab: SettingsTab {
        get { SettingsTab(rawValue: selectedTabRaw) ?? .general }
        nonmutating set { selectedTabRaw = newValue.rawValue }
    }
    @State private var isCustomModelMode: Bool = false
    @State private var statusClockNow: Date = Date()
    private let statusTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var newAPIKeyInput: String = ""
    @State private var revealedKeys: Set<String> = []
    @State private var testingKeys: Set<String> = []
    @State private var isTestingAllKeys: Bool = false
    @State private var keyRefreshTrigger: UUID = UUID()
    @State private var isRecordingTranslateShortcut: Bool = false
    @State private var isRecordingHistoryShortcut: Bool = false
    @State private var shortcutEventMonitor: Any? = nil
    @State private var selectedIgnoredAppId: String? = nil
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var showingClearConfirmation: Bool = false
    @State private var showingResetConfirmation: Bool = false
    @State private var newProjectNameInput: String = ""
    @State private var newGlossarySourceInput: String = ""
    @State private var newGlossaryTargetInput: String = ""
    @State private var glossarySearchQuery: String = ""
    @State private var showingRenameProjectPopover: Bool = false
    @State private var renameProjectDraft: String = ""
    @State private var showingVerifiedExamplesPopover: Bool = false
    @State private var showingPinnedItemsPopover: Bool = false
    @State private var didCopyGlossaryFeedback: Bool = false
    @State private var copiedGlossaryEntryId: UUID? = nil
    @State private var showingClearGlossaryConfirmation: Bool = false
    @State private var showingAPIKeyGuidePopover: Bool = false
    @State private var copiedAPIKeyFeedback: String? = nil
    @State private var didCopyAllKeysFeedback: Bool = false
    @State private var didCopyPromptFeedback: Bool = false
    @State private var isTestingSelectedModel: Bool = false
    @State private var selectedModelTestStatus: Bool? = nil
    @State private var copiedIgnoredAppBid: String? = nil
    @State private var showingClearIgnoredAppsConfirmation: Bool = false
    @State private var didCopyVersionInfoFeedback: Bool = false
    @State private var showingDeleteProjectConfirmation: Bool = false
    @State private var pendingDeleteCustomPromptId: UUID? = nil
    @State private var backupStatusMessage: String? = nil
    @State private var copiedPopoverItemId: UUID? = nil
    @State private var didCopyAllPopoverItemsFeedback: Bool = false
    @State private var pendingDeleteAPIKey: String? = nil
    @State private var newCustomPromptNameInput: String = ""
    @State private var selectedInspectorPromptId: String? = nil
    @FocusState private var isCustomPromptNameFocused: Bool

    public init(
        storageManager: StorageManager,
        updateManager: UpdateManager = .shared,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        onDismiss: (() -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.updateManager = updateManager
        self.hotKeyManager = hotKeyManager
        self.autoPasteService = autoPasteService
        self.onDismiss = onDismiss
    }

    private var isVi: Bool {
        loc.languageCode == "vi"
    }

    public var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(width: 510, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
            isCustomModelMode = !AppSettings.presetModels.contains(storageManager.settings.selectedModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
        }
        .onReceive(statusTimer) { tick in
            if selectedTab == .geminiAI {
                statusClockNow = tick
            }
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    // MARK: - Top Tab Bar (SuperClip Style — Zero Animation for Instant Response)

    private var topTabBar: some View {
        let missingAPIKey = storageManager.settings.validAPIKeys.isEmpty
        let hasUpdateBadge: Bool = {
            if case .updateAvailable = updateManager.status { return true }
            if case .readyToRestart = updateManager.status { return true }
            return false
        }()
        return HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: {
                    stopShortcutRecording()
                    selectedTab = tab
                }) {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 18, weight: .regular))
                                .frame(height: 22)

                            if tab == .geminiAI && missingAPIKey {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: 1)
                            } else if tab == .about && hasUpdateBadge {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: 1)
                            }
                        }
                        Text(tab.title)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? Color.secondary.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            VStack(spacing: 8) {
                switch selectedTab {
                case .general:
                    generalTabContent
                case .geminiAI:
                    geminiTabContent
                case .prompt:
                    promptTabContent
                case .projects:
                    projectsTabContent
                case .ignoredApps:
                    ignoredAppsTabContent
                case .about:
                    aboutTabContent
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab 1: General (SuperClip Card Style)

    private var generalTabContent: some View {
        VStack(spacing: 8) {
            languageAndHistoryCard
            optionsAndTriggersCard
            shortcutsCard
        }
    }

    private var languageAndHistoryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isVi ? "Ngôn ngữ & Lịch sử" : "Language & History")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(loc.tr(.defaultTargetLanguageLabel))
                        .font(.system(size: 11.5))
                        .frame(width: 155, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { storageManager.settings.targetLanguage },
                        set: { val in
                            var s = storageManager.settings
                            s.targetLanguage = val
                            storageManager.settings = s
                        }
                    )) {
                        ForEach(LanguageOption.supported) { opt in
                            Text(opt.displayName).tag(opt.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)

                    if storageManager.settings.targetLanguage != "Vietnamese" {
                        Button(action: {
                            var s = storageManager.settings
                            s.targetLanguage = "Vietnamese"
                            storageManager.settings = s
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(isVi ? "Đặt lại về Tiếng Việt (Mặc định)" : "Reset to Vietnamese (Default)")
                    }
                }

                HStack(spacing: 8) {
                    Text(loc.tr(.uiLanguageLabel))
                        .font(.system(size: 11.5))
                        .frame(width: 155, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { storageManager.settings.language },
                        set: { val in
                            var s = storageManager.settings
                            s.language = val
                            storageManager.settings = s
                        }
                    )) {
                        Text("Tiếng Việt").tag("vi")
                        Text("English").tag("en")
                        Text("System Default").tag("system")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)
                }

                HStack(spacing: 8) {
                    Text(loc.tr(.historyCapacityLabel))
                        .font(.system(size: 11.5))
                        .frame(width: 155, alignment: .leading)

                    TextField("", value: Binding(
                        get: { storageManager.settings.capacity },
                        set: { val in
                            var s = storageManager.settings
                            s.capacity = max(10, min(1000, val))
                            storageManager.settings = s
                        }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)

                    Stepper("", value: Binding(
                        get: { storageManager.settings.capacity },
                        set: { val in
                            var s = storageManager.settings
                            s.capacity = max(10, min(1000, val))
                            storageManager.settings = s
                        }
                    ), in: 10...1000, step: 10)
                    .labelsHidden()

                    Text(isVi ? "bản dịch" : "items")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                    Menu(isVi ? "Mức nhanh" : "Presets") {
                        ForEach([50, 100, 250, 500, 1000], id: \.self) { presetCap in
                            Button(presetCap == 100 ? (isVi ? "100 (Mặc định)" : "100 (Default)") : "\(presetCap)") {
                                var s = storageManager.settings
                                s.capacity = presetCap
                                storageManager.settings = s
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .fixedSize()

                    if storageManager.settings.capacity != 100 {
                        Button(action: {
                            var s = storageManager.settings
                            s.capacity = 100
                            storageManager.settings = s
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(isVi ? "Đặt lại về 100 bản dịch (Mặc định)" : "Reset to 100 items (Default)")
                    }
                }

                HStack(spacing: 8) {
                    Text(isVi ? "Kích thước Popup dịch:" : "Translation Popup Size:")
                        .font(.system(size: 11.5))
                        .frame(width: 155, alignment: .leading)

                    if let w = storageManager.settings.popupWidth, let h = storageManager.settings.popupHeight {
                        Text(isVi ? "Tuỳ chỉnh (\(Int(w)) × \(Int(h)) px)" : "Custom (\(Int(w)) × \(Int(h)) px)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)

                        Button(action: {
                            var s = storageManager.settings
                            s.popupWidth = nil
                            s.popupHeight = nil
                            storageManager.settings = s
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(isVi ? "Đặt lại tự động co giãn theo nội dung" : "Reset to auto-fit content")
                    } else {
                        Text(isVi ? "Tự động co giãn theo nội dung" : "Auto-fit content")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Menu(isVi ? "Cỡ nhanh" : "Presets") {
                        Button(isVi ? "Tự động co giãn (Mặc định)" : "Auto-fit Content (Default)") {
                            var s = storageManager.settings
                            s.popupWidth = nil
                            s.popupHeight = nil
                            storageManager.settings = s
                        }
                        Divider()
                        Button(isVi ? "Nhỏ gọn (420 × 280 px)" : "Compact (420 × 280 px)") {
                            var s = storageManager.settings
                            s.popupWidth = 420
                            s.popupHeight = 280
                            storageManager.settings = s
                        }
                        Button(isVi ? "Tiêu chuẩn (520 × 360 px)" : "Standard (520 × 360 px)") {
                            var s = storageManager.settings
                            s.popupWidth = 520
                            s.popupHeight = 360
                            storageManager.settings = s
                        }
                        Button(isVi ? "Rộng rãi (640 × 440 px)" : "Spacious (640 × 440 px)") {
                            var s = storageManager.settings
                            s.popupWidth = 640
                            s.popupHeight = 440
                            storageManager.settings = s
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var optionsAndTriggersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.tr(.triggerModeSection))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 5) {
                Toggle(loc.tr(.enableDoubleCopyTrigger), isOn: Binding(
                    get: { storageManager.settings.enableDoubleCopyTrigger },
                    set: { val in
                        var s = storageManager.settings
                        s.enableDoubleCopyTrigger = val
                        storageManager.settings = s
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Toggle(loc.tr(.enableAutoTranslateEveryCopy), isOn: Binding(
                    get: { storageManager.settings.autoTranslateEveryCopy },
                    set: { val in
                        var s = storageManager.settings
                        s.autoTranslateEveryCopy = val
                        storageManager.settings = s
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Divider().padding(.vertical, 2)

                Toggle(loc.tr(.launchAtLogin), isOn: Binding(
                    get: { storageManager.settings.launchAtLogin },
                    set: { val in
                        var s = storageManager.settings
                        s.launchAtLogin = val
                        storageManager.settings = s
                        LaunchAtLoginManager.shared.setEnabled(val)
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Toggle(isVi ? "Tự động kiểm tra bản cập nhật" : "Automatically check for updates", isOn: Binding(
                    get: { storageManager.settings.automaticallyCheckForUpdates },
                    set: { val in
                        var s = storageManager.settings
                        s.automaticallyCheckForUpdates = val
                        storageManager.settings = s
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Toggle(loc.tr(.recordTranslationHistory), isOn: Binding(
                    get: { storageManager.settings.recordHistory },
                    set: { val in
                        var s = storageManager.settings
                        s.recordHistory = val
                        storageManager.settings = s
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Toggle(loc.tr(.autoPasteOnSelection), isOn: Binding(
                    get: { storageManager.settings.autoPasteOnSelection },
                    set: { val in
                        var s = storageManager.settings
                        s.autoPasteOnSelection = val
                        storageManager.settings = s
                        isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                HStack(spacing: 6) {
                    Image(systemName: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(isAccessibilityTrusted ? .green : .orange)

                    Text("\(loc.tr(.accessibilityPermissionTitle)) \(isAccessibilityTrusted ? loc.tr(.accessibilityTrusted) : loc.tr(.accessibilityUntrusted))")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)

                    Spacer()

                    if !isAccessibilityTrusted {
                        Button(isVi ? "Kiểm tra lại" : "Recheck") {
                            isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 10.5))

                        Button(isVi ? "Mở Cài đặt Hệ thống" : "System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 10.5))

                        Button(loc.tr(.grantPermissionButton)) {
                            isAccessibilityTrusted = autoPasteService.resetAndRequestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .font(.system(size: 10.5))
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 2)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.tr(.tabShortcuts))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)

            // Row 1: Translate Shortcut
            HStack(spacing: 8) {
                Text(isVi ? "Dịch nhanh (Vùng chọn/Copy):" : "Quick Translate:")
                    .font(.system(size: 11.5))
                    .frame(width: 175, alignment: .leading)

                shortcutRecorderPill(
                    isRecording: isRecordingTranslateShortcut,
                    keyCode: storageManager.settings.translateHotKeyKeyCode,
                    modifiers: storageManager.settings.translateHotKeyModifiers,
                    onToggleRecord: {
                        if isRecordingTranslateShortcut {
                            stopShortcutRecording()
                        } else {
                            startShortcutRecording(forTranslate: true)
                        }
                    }
                )

                if storageManager.settings.translateHotKeyKeyCode != AppSettings.defaultTranslateHotKeyKeyCode ||
                   storageManager.settings.translateHotKeyModifiers != AppSettings.defaultTranslateHotKeyModifiers {
                    Button(action: {
                        stopShortcutRecording()
                        var s = storageManager.settings
                        s.translateHotKeyKeyCode = AppSettings.defaultTranslateHotKeyKeyCode
                        s.translateHotKeyModifiers = AppSettings.defaultTranslateHotKeyModifiers
                        storageManager.settings = s
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .help(loc.tr(.resetDefaultShortcutButton))
                }

                Spacer()

                Menu(isVi ? "Chọn nhanh" : "Presets") {
                    Button("Option + T (Default)") {
                        applyShortcut(forTranslate: true, keyCode: 17, modifiers: UInt32(optionKey))
                    }
                    Button("Option + D") {
                        applyShortcut(forTranslate: true, keyCode: 2, modifiers: UInt32(optionKey))
                    }
                    Button("Cmd + Shift + T") {
                        applyShortcut(forTranslate: true, keyCode: 17, modifiers: UInt32(cmdKey | shiftKey))
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
            }

            // Row 2: History Shortcut
            HStack(spacing: 8) {
                Text(isVi ? "Mở Lịch sử dịch tại chuột:" : "Floating History:")
                    .font(.system(size: 11.5))
                    .frame(width: 175, alignment: .leading)

                shortcutRecorderPill(
                    isRecording: isRecordingHistoryShortcut,
                    keyCode: storageManager.settings.historyHotKeyKeyCode,
                    modifiers: storageManager.settings.historyHotKeyModifiers,
                    onToggleRecord: {
                        if isRecordingHistoryShortcut {
                            stopShortcutRecording()
                        } else {
                            startShortcutRecording(forTranslate: false)
                        }
                    }
                )

                if storageManager.settings.historyHotKeyKeyCode != AppSettings.defaultHistoryHotKeyKeyCode ||
                   storageManager.settings.historyHotKeyModifiers != AppSettings.defaultHistoryHotKeyModifiers {
                    Button(action: {
                        stopShortcutRecording()
                        var s = storageManager.settings
                        s.historyHotKeyKeyCode = AppSettings.defaultHistoryHotKeyKeyCode
                        s.historyHotKeyModifiers = AppSettings.defaultHistoryHotKeyModifiers
                        storageManager.settings = s
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .help(loc.tr(.resetDefaultShortcutButton))
                }

                Spacer()

                Menu(isVi ? "Chọn nhanh" : "Presets") {
                    Button("Option + Shift + T (Default)") {
                        applyShortcut(forTranslate: false, keyCode: 17, modifiers: UInt32(optionKey | shiftKey))
                    }
                    Button("Option + H") {
                        applyShortcut(forTranslate: false, keyCode: 4, modifiers: UInt32(optionKey))
                    }
                    Button("Cmd + Shift + Y") {
                        applyShortcut(forTranslate: false, keyCode: 16, modifiers: UInt32(cmdKey | shiftKey))
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func shortcutRecorderPill(
        isRecording: Bool,
        keyCode: UInt32,
        modifiers: UInt32,
        onToggleRecord: @escaping () -> Void
    ) -> some View {
        Button(action: onToggleRecord) {
            HStack(spacing: 5) {
                if isRecording {
                    Image(systemName: "record.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(loc.tr(.pressShortcutPrompt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                } else {
                    Text(HotKeyManager.formatShortcut(keyCode: keyCode, modifiers: modifiers))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 1.5 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyShortcut(forTranslate: Bool, keyCode: UInt32, modifiers: UInt32) {
        stopShortcutRecording()
        var s = storageManager.settings
        if forTranslate {
            s.translateHotKeyKeyCode = keyCode
            s.translateHotKeyModifiers = modifiers
        } else {
            s.historyHotKeyKeyCode = keyCode
            s.historyHotKeyModifiers = modifiers
        }
        storageManager.settings = s
    }

    // MARK: - Tab 2: Gemini AI (Multi-Key Rotation, Verified Fast Models, Prompt)

    private var geminiTabContent: some View {
        VStack(spacing: 8) {
            apiKeysCard
            modelAndPromptCard
        }
    }

    private var apiKeysCard: some View {
        let validKeys = storageManager.settings.validAPIKeys
        let readyCount = validKeys.filter { key in
            let st = APIKeyRotator.shared.status(for: key, now: statusClockNow)
            if case .active = st { return true }
            if case .ready = st { return true }
            return false
        }.count
        let invalidKeys = validKeys.filter { key in
            if case .invalid = APIKeyRotator.shared.status(for: key, now: statusClockNow) { return true }
            return false
        }
        let allRevealed = !validKeys.isEmpty && validKeys.allSatisfy { revealedKeys.contains($0) }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc.tr(.geminiAPIKeysSection))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(validKeys.isEmpty
                     ? "(0 keys)"
                     : (isVi ? "(\(validKeys.count) keys · \(readyCount) sẵn sàng)" : "(\(validKeys.count) keys · \(readyCount) ready)"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(loc.tr(.geminiAPIKeysSubtitle))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            // Input bar with both Cmd+V support AND 1-click "Dán & Thêm" (Paste & Add) button
            HStack(spacing: 6) {
                TextField(loc.tr(.addAPIKeyPlaceholder), text: $newAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        addKeysFromInput()
                    }

                if !newAPIKeyInput.isEmpty {
                    Button(action: { newAPIKeyInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isVi ? "Xoá ô nhập" : "Clear input")
                }

                Button(action: pasteAndAddKeyFromClipboard) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text(isVi ? "Dán & Thêm" : "Paste & Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isVi ? "Dán trực tiếp API Key từ Clipboard và thêm vào danh sách" : "Paste API key from clipboard and add immediately")

                Button(action: addKeysFromInput) {
                    Text(loc.tr(.addAPIKeyButton))
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Key List Container (SuperClip list box style)
            if storageManager.settings.validAPIKeys.isEmpty {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "key")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                            Text(loc.tr(.noAPIKeysConfigured))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Button(action: pasteAndAddKeyFromClipboard) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 10))
                                        Text(isVi ? "Dán Key từ Clipboard" : "Paste from Clipboard")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button(action: {
                                    if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "safari")
                                            .font(.system(size: 10))
                                        Text(isVi ? "Lấy Key miễn phí (AI Studio)" : "Get Free Key (AI Studio)")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 2)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                    )
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(storageManager.settings.validAPIKeys.enumerated()), id: \.offset) { idx, key in
                            apiKeyRow(index: idx, key: key)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 165)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
                .id(keyRefreshTrigger)
            }

            HStack(spacing: 8) {
                if !storageManager.settings.validAPIKeys.isEmpty {
                    Button(action: testAllAPIKeys) {
                        HStack(spacing: 4) {
                            if isTestingAllKeys {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 10))
                            }
                            Text(loc.tr(.testAllKeysButton))
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingAllKeys)

                    Button(action: {
                        APIKeyRotator.shared.clearState()
                        keyRefreshTrigger = UUID()
                    }) {
                        Text(loc.tr(.clearCooldownsButton))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        if allRevealed {
                            revealedKeys.removeAll()
                        } else {
                            revealedKeys = Set(validKeys)
                        }
                    }) {
                        Image(systemName: allRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(allRevealed
                          ? (isVi ? "Ẩn tất cả API Key" : "Hide all API Keys")
                          : (isVi ? "Hiện tất cả API Key" : "Show all API Keys"))

                    Button(action: {
                        let joined = validKeys.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(joined, forType: .string)
                        didCopyAllKeysFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            didCopyAllKeysFeedback = false
                        }
                    }) {
                        Image(systemName: didCopyAllKeysFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(didCopyAllKeysFeedback ? .green : .primary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isVi ? "Sao chép toàn bộ danh sách API Key vào Clipboard" : "Copy all API Keys to Clipboard")

                    if !invalidKeys.isEmpty {
                        Button(action: {
                            for key in invalidKeys {
                                removeKey(key)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text(isVi ? "Xoá Key lỗi (\(invalidKeys.count))" : "Remove Invalid (\(invalidKeys.count))")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(isVi ? "Xoá tất cả các API Key không hợp lệ khỏi danh sách" : "Remove all invalid API Keys from the list")
                    }
                }

                Spacer()

                Button(action: {
                    showingAPIKeyGuidePopover.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 11))
                        Text(isVi ? "Hướng dẫn tạo Key" : "How to get API Key")
                            .font(.system(size: 11, weight: .medium))
                            .underline()
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingAPIKeyGuidePopover, arrowEdge: .top) {
                    apiKeyGuidePopoverContent
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var apiKeyGuidePopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "key.radiowaves.forward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(isVi ? "Hướng dẫn lấy Gemini API Key miễn phí" : "How to Get a Free Gemini API Key")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.primary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(isVi
                     ? "1. Mở trang Google AI Studio và đăng nhập bằng tài khoản Google của bạn."
                     : "1. Open Google AI Studio and sign in with your Google account.")
                    .font(.system(size: 11.5))

                Text(isVi
                     ? "2. Bấm nút \"Create API key\" → Chọn \"Create API key in new project\" → Sao chép (Copy) mã key bắt đầu bằng AIzaSy..."
                     : "2. Click \"Create API key\" → Select \"Create API key in new project\" → Copy the generated key (starts with AIzaSy...).")
                    .font(.system(size: 11.5))

                Text(isVi
                     ? "3. Quay lại cửa sổ này và bấm nút \"Dán & Thêm\"."
                     : "3. Return here and click \"Paste & Add\".")
                    .font(.system(size: 11.5))

                Text(isVi
                     ? "Mẹo: Bạn có thể tạo 2–5 API Key ở các project khác nhau và thêm vào danh sách để SuperTrans tự động xoay vòng khi hết hạn mức (RPM/RPD)."
                     : "Tip: Create 2–5 API keys across different projects so SuperTrans can automatically rotate them when rate limits are reached.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(action: {
                    if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "safari")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isVi ? "Mở Google AI Studio (aistudio.google.com)" : "Open Google AI Studio (aistudio.google.com)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    pasteAndAddKeyFromClipboard()
                    showingAPIKeyGuidePopover = false
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(isVi ? "Dán & Thêm ngay" : "Paste & Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.14)))
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 390)
    }

    private func apiKeyRow(index: Int, key: String) -> some View {
        let isRevealed = revealedKeys.contains(key)
        let isTesting = testingKeys.contains(key)
        let status = APIKeyRotator.shared.status(for: key, now: statusClockNow)
        let totalKeys = storageManager.settings.validAPIKeys.count

        return HStack(spacing: 5) {
            Text("#\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .leading)

            if totalKeys > 1 {
                HStack(spacing: 1) {
                    Button(action: {
                        moveAPIKey(at: index, offset: -1)
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 13, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help(isVi ? "Đưa Key lên ưu tiên trước" : "Move key up")

                    Button(action: {
                        moveAPIKey(at: index, offset: 1)
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 13, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .disabled(index >= totalKeys - 1)
                    .help(isVi ? "Đưa Key xuống dưới" : "Move key down")
                }
            }

            Text(isRevealed ? key : APIKeyRotator.maskKey(key))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge(for: status)

            Button(action: {
                if isRevealed {
                    revealedKeys.remove(key)
                } else {
                    revealedKeys.insert(key)
                }
            }) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 10.5))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? (isVi ? "Ẩn API Key" : "Hide API Key") : (isVi ? "Hiện API Key" : "Show API Key"))

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                copiedAPIKeyFeedback = key
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedAPIKeyFeedback == key {
                        copiedAPIKeyFeedback = nil
                    }
                }
            }) {
                Image(systemName: copiedAPIKeyFeedback == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(copiedAPIKeyFeedback == key ? .green : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isVi ? "Sao chép API Key này" : "Copy this API Key")

            Button(action: {
                testSingleKey(key)
            }) {
                if isTesting {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(loc.tr(.testSingleKeyButton))
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isTesting)

            Button(action: {
                pendingDeleteAPIKey = key
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10.5))
                    .foregroundColor(.red)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isVi ? "Xoá API Key này" : "Remove this API Key")
            .confirmationDialog(
                isVi ? "Xoá Gemini API Key (\(APIKeyRotator.maskKey(key))) khỏi danh sách?" : "Remove Gemini API Key (\(APIKeyRotator.maskKey(key))) from the list?",
                isPresented: Binding(
                    get: { pendingDeleteAPIKey == key },
                    set: { if !$0 { pendingDeleteAPIKey = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(isVi ? "Xoá API Key" : "Remove API Key", role: .destructive) {
                    removeKey(key)
                    pendingDeleteAPIKey = nil
                }
                Button(isVi ? "Hủy" : "Cancel", role: .cancel) {
                    pendingDeleteAPIKey = nil
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .contextMenu {
            if index > 0 {
                Button(isVi ? "Đặt làm Key ưu tiên #1" : "Make Primary Key (#1)") {
                    moveAPIKey(at: index, offset: -index)
                }
                Divider()
            }
            Button(isVi ? "Kiểm tra Key này" : "Test This Key") {
                testSingleKey(key)
            }
            Button(isVi ? "Sao chép API Key" : "Copy API Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                copiedAPIKeyFeedback = key
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedAPIKeyFeedback == key {
                        copiedAPIKeyFeedback = nil
                    }
                }
            }
            Button(isRevealed ? (isVi ? "Ẩn API Key" : "Hide API Key") : (isVi ? "Hiện API Key" : "Show API Key")) {
                if isRevealed {
                    revealedKeys.remove(key)
                } else {
                    revealedKeys.insert(key)
                }
            }
            Divider()
            Button(isVi ? "Xoá API Key..." : "Remove API Key...", role: .destructive) {
                pendingDeleteAPIKey = key
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: APIKeyStatus) -> some View {
        switch status {
        case .active:
            HStack(spacing: 3) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(loc.tr(.keyStatusActive)).font(.system(size: 10, weight: .medium)).foregroundColor(.green)
            }
        case .ready:
            HStack(spacing: 3) {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                Text(loc.tr(.keyStatusReady)).font(.system(size: 10)).foregroundColor(.secondary)
            }
        case .rateLimited(let until):
            let remaining = APIKeyRotator.formatRemainingTime(until: until, now: statusClockNow)
            HStack(spacing: 3) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text(isVi ? "Tạm nghỉ RPM (\(remaining))" : "RPM Cooldown (\(remaining))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
            }
        case .quotaExhausted(let until):
            let remaining = APIKeyRotator.formatRemainingTime(until: until, now: statusClockNow)
            HStack(spacing: 3) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(isVi ? "Hết Quota ngày (\(remaining))" : "Daily Quota (\(remaining))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
        case .invalid:
            HStack(spacing: 3) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(loc.tr(.keyStatusInvalid)).font(.system(size: 10, weight: .medium)).foregroundColor(.red)
            }
        }
    }

    private func modelDisplayLabel(for modelId: String) -> String {
        switch modelId {
        case "gemini-3.1-flash-lite":
            return isVi ? "gemini-3.1-flash-lite (Nhanh nhất — Khuyên dùng)" : "gemini-3.1-flash-lite (Fastest — Recommended)"
        case "gemini-3.5-flash-lite":
            return isVi ? "gemini-3.5-flash-lite (Rất nhanh)" : "gemini-3.5-flash-lite (Very Fast)"
        case "gemini-3-flash-preview":
            return isVi ? "gemini-3-flash-preview (Cân bằng)" : "gemini-3-flash-preview (Balanced)"
        case "gemini-3.5-flash":
            return isVi ? "gemini-3.5-flash (Chất lượng cao)" : "gemini-3.5-flash (High Quality)"
        default:
            return modelId
        }
    }

    private var modelAndPromptCard: some View {
        let showCustomInput = isCustomModelMode || !AppSettings.presetModels.contains(storageManager.settings.selectedModel)
        let pickerSelection = Binding<String>(
            get: {
                if showCustomInput {
                    return "__custom__"
                }
                return storageManager.settings.selectedModel
            },
            set: { val in
                selectedModelTestStatus = nil
                if val == "__custom__" {
                    isCustomModelMode = true
                } else {
                    isCustomModelMode = false
                    var s = storageManager.settings
                    s.selectedModel = val
                    storageManager.settings = s
                }
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text(loc.tr(.geminiModelSection))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                Text(isVi ? "Chọn Model:" : "Select Model:")
                    .font(.system(size: 11.5))
                    .frame(width: 85, alignment: .leading)

                Picker("", selection: pickerSelection) {
                    ForEach(AppSettings.presetModels, id: \.self) { preset in
                        Text(modelDisplayLabel(for: preset)).tag(preset)
                    }
                    Divider()
                    Text(isVi ? "Nhập Model ID tuỳ chỉnh..." : "Custom Model ID...").tag("__custom__")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if storageManager.settings.selectedModel != AppSettings.defaultModel || showCustomInput {
                    Button(action: {
                        isCustomModelMode = false
                        selectedModelTestStatus = nil
                        var s = storageManager.settings
                        s.selectedModel = AppSettings.defaultModel
                        storageManager.settings = s
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isVi ? "Đặt lại về Model nhanh nhất khuyên dùng (\(AppSettings.defaultModel))" : "Reset to fastest recommended model (\(AppSettings.defaultModel))")
                }

                if !storageManager.settings.validAPIKeys.isEmpty {
                    Button(action: testSelectedModel) {
                        HStack(spacing: 4) {
                            if isTestingSelectedModel {
                                ProgressView().controlSize(.mini)
                            } else if let status = selectedModelTestStatus {
                                Image(systemName: status ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(status ? .green : .orange)
                            } else {
                                Image(systemName: "bolt.horizontal")
                                    .font(.system(size: 10))
                            }
                            Text(isVi ? "Kiểm tra Model" : "Test Model")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingSelectedModel || storageManager.settings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(isVi ? "Kiểm tra kết nối thực tế tới Model đang chọn bằng API Key hiện tại" : "Test connection to the selected Model using your active API Key")
                }
            }

            if showCustomInput {
                HStack(spacing: 8) {
                    Text(isVi ? "Model ID:" : "Model ID:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 85, alignment: .leading)
                    TextField(loc.tr(.customModelPlaceholder), text: Binding(
                        get: { storageManager.settings.selectedModel },
                        set: { val in
                            selectedModelTestStatus = nil
                            var s = storageManager.settings
                            s.selectedModel = val
                            storageManager.settings = s
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))

                    if !storageManager.settings.selectedModel.isEmpty {
                        Button(action: {
                            selectedModelTestStatus = nil
                            var s = storageManager.settings
                            s.selectedModel = ""
                            storageManager.settings = s
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isVi ? "Xoá Model ID" : "Clear Model ID")
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Tab 3: Prompt (Master-Detail List + Editor with Hide/Show & Custom Prompts)

    private var currentPromptPresetId: String {
        storageManager.settings.resolvedActivePromptId
    }

    private var effectiveInspectedPromptId: String {
        if let inspected = selectedInspectorPromptId {
            if AppSettings.promptPresets.contains(where: { $0.id == inspected }) ||
               storageManager.settings.customPromptPresets.contains(where: { $0.id.uuidString == inspected }) {
                return inspected
            }
        }
        return currentPromptPresetId
    }

    private func createNewCustomPromptPreset(basePrompt: String? = nil, baseName: String? = nil) {
        var s = storageManager.settings
        let nextIndex = s.customPromptPresets.count + 1
        let defaultName = isVi ? "Prompt tuỳ chỉnh #\(nextIndex)" : "Custom Prompt #\(nextIndex)"
        let finalName = baseName ?? defaultName
        let initialPrompt = basePrompt ?? AppSettings.defaultSystemPrompt

        let newPreset = CustomPromptPreset(
            name: finalName,
            prompt: initialPrompt,
            isHidden: false
        )
        s.customPromptPresets.append(newPreset)
        s.selectedPromptId = newPreset.id.uuidString
        s.customSystemPrompt = newPreset.prompt
        storageManager.settings = s
        selectedInspectorPromptId = newPreset.id.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isCustomPromptNameFocused = true
        }
    }

    private func deleteCustomPromptPreset(id: UUID) {
        var s = storageManager.settings
        s.customPromptPresets.removeAll { $0.id == id }
        if s.resolvedActivePromptId == id.uuidString {
            s.selectFirstVisiblePrompt()
        }
        storageManager.settings = s
        if selectedInspectorPromptId == id.uuidString {
            selectedInspectorPromptId = s.resolvedActivePromptId
        }
    }

    private func moveCustomPromptPreset(id: UUID, direction: Int) {
        var s = storageManager.settings
        guard let idx = s.customPromptPresets.firstIndex(where: { $0.id == id }) else { return }
        let targetIdx = idx + direction
        guard targetIdx >= 0 && targetIdx < s.customPromptPresets.count else { return }
        s.customPromptPresets.swapAt(idx, targetIdx)
        storageManager.settings = s
    }

    private func applyCustomPromptTemplate(id: UUID, template: String) {
        var s = storageManager.settings
        guard let idx = s.customPromptPresets.firstIndex(where: { $0.id == id }) else { return }
        s.customPromptPresets[idx].prompt = template
        if s.resolvedActivePromptId == id.uuidString {
            s.customSystemPrompt = template
        }
        storageManager.settings = s
    }

    private func copyPromptToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopyPromptFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyPromptFeedback = false
        }
    }

    private func toggleBuiltinPromptHidden(_ id: String) {
        var s = storageManager.settings
        let isCurrentlyHidden = s.isBuiltinPromptHidden(id)
        if isCurrentlyHidden {
            s.hiddenBuiltinPromptIds.removeAll { $0 == id }
        } else {
            guard s.totalVisiblePromptCount > 1 else { return }
            if !s.hiddenBuiltinPromptIds.contains(id) {
                s.hiddenBuiltinPromptIds.append(id)
            }
            if s.resolvedActivePromptId == id {
                s.selectFirstVisiblePrompt()
                selectedInspectorPromptId = s.resolvedActivePromptId
            }
        }
        storageManager.settings = s
    }

    private func toggleCustomPromptHidden(_ id: UUID) {
        var s = storageManager.settings
        guard let idx = s.customPromptPresets.firstIndex(where: { $0.id == id }) else { return }
        let isCurrentlyHidden = s.customPromptPresets[idx].isHidden
        if isCurrentlyHidden {
            s.customPromptPresets[idx].isHidden = false
        } else {
            guard s.totalVisiblePromptCount > 1 else { return }
            s.customPromptPresets[idx].isHidden = true
            if s.resolvedActivePromptId == id.uuidString {
                s.selectFirstVisiblePrompt()
                selectedInspectorPromptId = s.resolvedActivePromptId
            }
        }
        storageManager.settings = s
    }

    private func showAllPrompts() {
        var s = storageManager.settings
        s.hiddenBuiltinPromptIds = []
        for idx in s.customPromptPresets.indices {
            s.customPromptPresets[idx].isHidden = false
        }
        storageManager.settings = s
    }

    private var promptTabContent: some View {
        let settings = storageManager.settings
        let activeId = settings.resolvedActivePromptId
        let inspectedId = effectiveInspectedPromptId
        let canHideMore = settings.totalVisiblePromptCount > 1

        return VStack(alignment: .leading, spacing: 8) {
            // Top Header Row
            HStack(spacing: 8) {
                Text(loc.tr(.systemPromptSection))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(isVi ? "(\(settings.totalVisiblePromptCount) hiển thị trên Popup)" : "(\(settings.totalVisiblePromptCount) visible in Popup)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                if settings.hasAnyHiddenPrompt {
                    Button(action: showAllPrompts) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye")
                                .font(.system(size: 10))
                            Text(isVi ? "Hiện tất cả" : "Show All")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: {
                    createNewCustomPromptPreset()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10.5))
                        Text(isVi ? "Thêm Prompt mới" : "New Custom Prompt")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // 2-Column Master-Detail Layout (Left: Prompt List with Hide/Show, Right: Prompt Editor)
            HStack(alignment: .top, spacing: 10) {
                // Left Column: Master List of Built-in & Custom Prompts
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isVi ? "MẪU CÓ SẴN" : "BUILT-IN PRESETS")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                            .padding(.bottom, 1)

                        ForEach(AppSettings.promptPresets) { preset in
                            let isHidden = settings.isBuiltinPromptHidden(preset.id)
                            let isActive = (activeId == preset.id)
                            let isSelected = (inspectedId == preset.id)

                            HStack(spacing: 5) {
                                Button(action: {
                                    selectedInspectorPromptId = preset.id
                                    if !isHidden {
                                        var s = storageManager.settings
                                        s.selectedPromptId = preset.id
                                        s.customSystemPrompt = preset.prompt
                                        storageManager.settings = s
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isActive ? Color.green : Color.clear)
                                            .frame(width: 6, height: 6)

                                        Text(isVi ? preset.shortTitleVi : preset.shortTitleEn)
                                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(isHidden ? .secondary.opacity(0.6) : .primary)
                                            .strikethrough(isHidden, color: .secondary.opacity(0.6))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    toggleBuiltinPromptHidden(preset.id)
                                }) {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isHidden ? .secondary.opacity(0.5) : .accentColor)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.borderless)
                                .disabled(!isHidden && !canHideMore)
                                .help(isHidden
                                      ? (isVi ? "Đang ẩn khỏi Popup — Bấm để hiển thị" : "Hidden from Popup — Click to show")
                                      : (isVi ? "Đang hiển thị trên Popup — Bấm để ẩn" : "Visible in Popup — Click to hide"))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                            )
                            .contextMenu {
                                Button(isHidden ? (isVi ? "Hiện & Dùng Prompt này" : "Show & Use This Prompt") : (isVi ? "Dùng Prompt này" : "Use This Prompt")) {
                                    var s = storageManager.settings
                                    s.hiddenBuiltinPromptIds.removeAll { $0 == preset.id }
                                    s.selectedPromptId = preset.id
                                    s.customSystemPrompt = preset.prompt
                                    storageManager.settings = s
                                    selectedInspectorPromptId = preset.id
                                }
                                Button(isVi ? "Tạo bản sao để sửa" : "Duplicate to Edit") {
                                    let baseTitle = (isVi ? preset.shortTitleVi : preset.shortTitleEn) + (isVi ? " (Bản sao)" : " (Copy)")
                                    createNewCustomPromptPreset(basePrompt: preset.prompt, baseName: baseTitle)
                                }
                                Button(isVi ? "Sao chép nội dung Prompt" : "Copy Prompt Text") {
                                    copyPromptToClipboard(preset.prompt)
                                }
                                if isHidden || canHideMore {
                                    Divider()
                                    Button(isHidden ? (isVi ? "Hiển thị lại trên Popup" : "Show in Popup") : (isVi ? "Ẩn khỏi Popup" : "Hide from Popup")) {
                                        toggleBuiltinPromptHidden(preset.id)
                                    }
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text(isVi ? "PROMPT TỰ THÊM" : "CUSTOM PROMPTS")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(settings.customPromptPresets.count)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 1)

                        if settings.customPromptPresets.isEmpty {
                            Text(isVi ? "Chưa có Custom Prompt.\nBấm \"+ Thêm Prompt mới\" ở trên." : "No custom prompts yet.\nClick \"+ New Custom Prompt\" above.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                        } else {
                            let customCount = settings.customPromptPresets.count
                            ForEach(Array(settings.customPromptPresets.enumerated()), id: \.element.id) { index, customPreset in
                                let isHidden = customPreset.isHidden
                                let isActive = (activeId == customPreset.id.uuidString)
                                let isSelected = (inspectedId == customPreset.id.uuidString)
                                let displayTitle = customPreset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (isVi ? "Prompt tuỳ chỉnh" : "Custom Prompt")
                                    : customPreset.name

                                HStack(spacing: 3) {
                                    Button(action: {
                                        selectedInspectorPromptId = customPreset.id.uuidString
                                        if !isHidden {
                                            var s = storageManager.settings
                                            s.selectedPromptId = customPreset.id.uuidString
                                            s.customSystemPrompt = customPreset.prompt
                                            storageManager.settings = s
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(isActive ? Color.green : Color.clear)
                                                .frame(width: 6, height: 6)

                                            Text(displayTitle)
                                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(isHidden ? .secondary.opacity(0.6) : .primary)
                                                .strikethrough(isHidden, color: .secondary.opacity(0.6))
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if customCount > 1 {
                                        VStack(spacing: 1) {
                                            Button(action: {
                                                moveCustomPromptPreset(id: customPreset.id, direction: -1)
                                            }) {
                                                Image(systemName: "chevron.up")
                                                    .font(.system(size: 7.5, weight: .bold))
                                                    .foregroundColor(index == 0 ? .secondary.opacity(0.3) : .secondary)
                                                    .frame(width: 12, height: 9)
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(index == 0)
                                            .help(isVi ? "Đưa lên trên" : "Move up")

                                            Button(action: {
                                                moveCustomPromptPreset(id: customPreset.id, direction: 1)
                                            }) {
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 7.5, weight: .bold))
                                                    .foregroundColor(index == customCount - 1 ? .secondary.opacity(0.3) : .secondary)
                                                    .frame(width: 12, height: 9)
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(index == customCount - 1)
                                            .help(isVi ? "Đưa xuống dưới" : "Move down")
                                        }
                                    }

                                    Button(action: {
                                        toggleCustomPromptHidden(customPreset.id)
                                    }) {
                                        Image(systemName: isHidden ? "eye.slash" : "eye")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(isHidden ? .secondary.opacity(0.5) : .accentColor)
                                            .frame(width: 18, height: 20)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(!isHidden && !canHideMore)
                                    .help(isHidden
                                          ? (isVi ? "Đang ẩn khỏi Popup — Bấm để hiển thị" : "Hidden from Popup — Click to show")
                                          : (isVi ? "Đang hiển thị trên Popup — Bấm để ẩn" : "Visible in Popup — Click to hide"))

                                    Button(action: {
                                        pendingDeleteCustomPromptId = customPreset.id
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red.opacity(0.85))
                                            .frame(width: 18, height: 20)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(isVi ? "Xoá Custom Prompt này" : "Delete this Custom Prompt")
                                    .confirmationDialog(
                                        isVi ? "Xoá Custom Prompt \"\(displayTitle)\"?" : "Delete Custom Prompt \"\(displayTitle)\"?",
                                        isPresented: Binding(
                                            get: { pendingDeleteCustomPromptId == customPreset.id },
                                            set: { if !$0 { pendingDeleteCustomPromptId = nil } }
                                        ),
                                        titleVisibility: .visible
                                    ) {
                                        Button(isVi ? "Xoá Custom Prompt" : "Delete Custom Prompt", role: .destructive) {
                                            deleteCustomPromptPreset(id: customPreset.id)
                                            pendingDeleteCustomPromptId = nil
                                        }
                                        Button(isVi ? "Hủy" : "Cancel", role: .cancel) {
                                            pendingDeleteCustomPromptId = nil
                                        }
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                                )
                                .contextMenu {
                                    Button(isHidden ? (isVi ? "Hiện & Dùng Prompt này" : "Show & Use This Prompt") : (isVi ? "Dùng Prompt này" : "Use This Prompt")) {
                                        var s = storageManager.settings
                                        if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                            s.customPromptPresets[idx].isHidden = false
                                            s.selectedPromptId = customPreset.id.uuidString
                                            s.customSystemPrompt = s.customPromptPresets[idx].prompt
                                            storageManager.settings = s
                                            selectedInspectorPromptId = customPreset.id.uuidString
                                        }
                                    }
                                    Button(isVi ? "Nhân bản Custom Prompt" : "Duplicate Custom Prompt") {
                                        let copyTitle = displayTitle + (isVi ? " (Bản sao)" : " (Copy)")
                                        createNewCustomPromptPreset(basePrompt: customPreset.prompt, baseName: copyTitle)
                                    }
                                    Button(isVi ? "Sao chép nội dung Prompt" : "Copy Prompt Text") {
                                        copyPromptToClipboard(customPreset.prompt)
                                    }
                                    if isHidden || canHideMore {
                                        Button(isHidden ? (isVi ? "Hiển thị lại trên Popup" : "Show in Popup") : (isVi ? "Ẩn khỏi Popup" : "Hide from Popup")) {
                                            toggleCustomPromptHidden(customPreset.id)
                                        }
                                    }
                                    Divider()
                                    Button(isVi ? "Xoá Custom Prompt..." : "Delete Custom Prompt...", role: .destructive) {
                                        pendingDeleteCustomPromptId = customPreset.id
                                    }
                                }
                            }
                        }
                    }
                    .padding(5)
                }
                .frame(width: 200, height: 344)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )

                // Right Column: Detail Inspector & Editor
                VStack(alignment: .leading, spacing: 6) {
                    if let customPreset = settings.customPromptPresets.first(where: { $0.id.uuidString == inspectedId }) {
                        let isCustomActive = (activeId == customPreset.id.uuidString)
                        HStack(spacing: 6) {
                            Text(isVi ? "Tên:" : "Name:")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.secondary)

                            ZStack(alignment: .trailing) {
                                TextField(
                                    isVi ? "Nhập tên Custom Prompt..." : "Enter Custom Prompt name...",
                                    text: Binding(
                                        get: {
                                            storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.name ?? customPreset.name
                                        },
                                        set: { newName in
                                            var s = storageManager.settings
                                            if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                                s.customPromptPresets[idx].name = newName
                                                storageManager.settings = s
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, weight: .medium))
                                .focused($isCustomPromptNameFocused)

                                let currentCustomName = storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.name ?? customPreset.name
                                if !currentCustomName.isEmpty {
                                    Button(action: {
                                        var s = storageManager.settings
                                        if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                            s.customPromptPresets[idx].name = ""
                                            storageManager.settings = s
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 6)
                                    .help(isVi ? "Xoá tên Custom Prompt" : "Clear Custom Prompt name")
                                }
                            }

                            if isCustomActive {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 5, height: 5)
                                    Text(isVi ? "Đang dùng" : "Active")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                            } else if customPreset.isHidden {
                                Button(action: {
                                    var s = storageManager.settings
                                    if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                        s.customPromptPresets[idx].isHidden = false
                                        s.selectedPromptId = customPreset.id.uuidString
                                        s.customSystemPrompt = s.customPromptPresets[idx].prompt
                                        storageManager.settings = s
                                    }
                                }) {
                                    Text(isVi ? "Hiện & Dùng" : "Show & Use")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button(action: {
                                    var s = storageManager.settings
                                    s.selectedPromptId = customPreset.id.uuidString
                                    s.customSystemPrompt = customPreset.prompt
                                    storageManager.settings = s
                                }) {
                                    Text(isVi ? "Dùng" : "Use")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(action: {
                                let currentText = storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.prompt ?? customPreset.prompt
                                copyPromptToClipboard(currentText)
                            }) {
                                Image(systemName: didCopyPromptFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(didCopyPromptFeedback ? .green : .secondary)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(isVi ? "Sao chép nội dung Prompt" : "Copy Prompt text")

                            Button(action: {
                                let currentObj = storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id }) ?? customPreset
                                let copyTitle = currentObj.name + (isVi ? " (Bản sao)" : " (Copy)")
                                createNewCustomPromptPreset(basePrompt: currentObj.prompt, baseName: copyTitle)
                            }) {
                                Image(systemName: "plus.square.on.square")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(isVi ? "Nhân bản Custom Prompt này" : "Duplicate this Custom Prompt")

                            if customPreset.prompt != AppSettings.defaultSystemPrompt {
                                Button(action: {
                                    var s = storageManager.settings
                                    if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                        s.customPromptPresets[idx].prompt = AppSettings.defaultSystemPrompt
                                        if s.resolvedActivePromptId == customPreset.id.uuidString {
                                            s.customSystemPrompt = AppSettings.defaultSystemPrompt
                                        }
                                        storageManager.settings = s
                                    }
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(isVi ? "Đặt lại nội dung về mẫu mặc định" : "Reset content to default template")
                            }
                        }

                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: Binding(
                                get: {
                                    storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.prompt ?? customPreset.prompt
                                },
                                set: { newPrompt in
                                    var s = storageManager.settings
                                    if let idx = s.customPromptPresets.firstIndex(where: { $0.id == customPreset.id }) {
                                        s.customPromptPresets[idx].prompt = newPrompt
                                        if s.resolvedActivePromptId == customPreset.id.uuidString {
                                            s.customSystemPrompt = newPrompt
                                        }
                                        storageManager.settings = s
                                    }
                                }
                            ))
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(6)
                            .frame(maxWidth: .infinity, minHeight: 312, maxHeight: 312)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                            )

                            let charCount = (storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.prompt ?? customPreset.prompt).count
                            HStack {
                                Menu(isVi ? "Mẫu nhanh" : "Templates") {
                                    Button(isVi ? "Dịch thuật chuẩn xác & Tự nhiên (Mặc định)" : "Accurate & Natural Translation (Default)") {
                                        applyCustomPromptTemplate(id: customPreset.id, template: AppSettings.defaultSystemPrompt)
                                    }
                                    Button(isVi ? "Hiệu đính & Tự nhiên hoá câu văn" : "Proofread & Naturalize Tone") {
                                        applyCustomPromptTemplate(
                                            id: customPreset.id,
                                            template: isVi
                                                ? "Dịch văn bản sang {{TARGET_LANGUAGE}} với văn phong cực kỳ tự nhiên, mạch lạc, trau chuốt như người bản xứ. Chỉ trả về kết quả dịch cuối cùng, không giải thích."
                                                : "Translate the text into {{TARGET_LANGUAGE}} with a natural, fluent, native-sounding tone. Return ONLY the final translated text without explanation."
                                        )
                                    }
                                    Button(isVi ? "Tóm tắt ý chính (Bullet points)" : "Summarize Key Points (Bullets)") {
                                        applyCustomPromptTemplate(
                                            id: customPreset.id,
                                            template: isVi
                                                ? "Dịch và tóm tắt các ý chính của văn bản sang {{TARGET_LANGUAGE}} dưới dạng gạch đầu dòng ngắn gọn, súc tích. Chỉ trả về kết quả, không dẫn nhập."
                                                : "Translate and summarize the key points of the text into {{TARGET_LANGUAGE}} as concise bullet points. Return ONLY the bullet points."
                                        )
                                    }
                                    Button(isVi ? "Dịch kèm giải thích thuật ngữ quan trọng" : "Translate + Explain Key Terms") {
                                        applyCustomPromptTemplate(
                                            id: customPreset.id,
                                            template: isVi
                                                ? "Dịch văn bản sang {{TARGET_LANGUAGE}} chính xác. Sau bản dịch, liệt kê ngắn gọn tối đa 3 thuật ngữ/từ vựng quan trọng kèm giải nghĩa ngắn."
                                                : "Translate the text accurately into {{TARGET_LANGUAGE}}. Below the translation, briefly list up to 3 key terms or vocabulary items with short explanations."
                                        )
                                    }
                                }
                                .menuStyle(.borderedButton)
                                .controlSize(.mini)
                                .fixedSize()

                                Button(action: {
                                    if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !pasted.isEmpty {
                                        applyCustomPromptTemplate(id: customPreset.id, template: pasted)
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 9))
                                        Text(isVi ? "Dán" : "Paste")
                                            .font(.system(size: 9.5))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help(isVi ? "Dán nội dung Prompt từ Clipboard" : "Paste Prompt content from Clipboard")

                                Button(action: {
                                    let currentPrompt = storageManager.settings.customPromptPresets.first(where: { $0.id == customPreset.id })?.prompt ?? customPreset.prompt
                                    let separator = (currentPrompt.isEmpty || currentPrompt.hasSuffix(" ") || currentPrompt.hasSuffix("\n")) ? "" : " "
                                    applyCustomPromptTemplate(id: customPreset.id, template: currentPrompt + separator + "{{TARGET_LANGUAGE}}")
                                }) {
                                    Text("+ {{TARGET_LANGUAGE}}")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help(isVi ? "Chèn biến ngôn ngữ đích (SuperTrans sẽ tự thay bằng ngôn ngữ đích đang chọn)" : "Insert target language placeholder (automatically replaced with the active target language)")

                                if charCount > 0 {
                                    Button(action: {
                                        applyCustomPromptTemplate(id: customPreset.id, template: "")
                                    }) {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 9.5))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help(isVi ? "Xoá trắng nội dung Custom Prompt" : "Clear Custom Prompt text")
                                }

                                Spacer()

                                Text(isVi ? "\(charCount) ký tự" : "\(charCount) chars")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                                    .cornerRadius(4)
                                    .allowsHitTesting(false)
                            }
                            .padding(6)
                        }
                    } else if let builtinPreset = AppSettings.promptPresets.first(where: { $0.id == inspectedId }) ?? AppSettings.promptPresets.first {
                        let isHidden = settings.isBuiltinPromptHidden(builtinPreset.id)
                        let isBuiltinActive = (activeId == builtinPreset.id)
                        HStack(spacing: 6) {
                            Text(isVi ? builtinPreset.titleVi : builtinPreset.titleEn)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            if isBuiltinActive {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 5, height: 5)
                                    Text(isVi ? "Đang dùng" : "Active")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                            } else if isHidden {
                                Button(action: {
                                    var s = storageManager.settings
                                    s.hiddenBuiltinPromptIds.removeAll { $0 == builtinPreset.id }
                                    s.selectedPromptId = builtinPreset.id
                                    s.customSystemPrompt = builtinPreset.prompt
                                    storageManager.settings = s
                                }) {
                                    Text(isVi ? "Hiện & Dùng" : "Show & Use")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button(action: {
                                    var s = storageManager.settings
                                    s.selectedPromptId = builtinPreset.id
                                    s.customSystemPrompt = builtinPreset.prompt
                                    storageManager.settings = s
                                }) {
                                    Text(isVi ? "Dùng" : "Use")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(action: {
                                copyPromptToClipboard(builtinPreset.prompt)
                            }) {
                                Image(systemName: didCopyPromptFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(didCopyPromptFeedback ? .green : .secondary)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(isVi ? "Sao chép nội dung Prompt" : "Copy Prompt text")

                            Button(action: {
                                let baseTitle = (isVi ? builtinPreset.shortTitleVi : builtinPreset.shortTitleEn) + (isVi ? " (Bản sao)" : " (Copy)")
                                createNewCustomPromptPreset(basePrompt: builtinPreset.prompt, baseName: baseTitle)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus.square.on.square")
                                        .font(.system(size: 9.5))
                                    Text(isVi ? "Tạo bản sao để sửa" : "Duplicate to Edit")
                                        .font(.system(size: 10.5))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ZStack(alignment: .bottomTrailing) {
                            ScrollView {
                                Text(builtinPreset.prompt)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 312, maxHeight: 312)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                            )

                            Text(isVi ? "\(builtinPreset.prompt.count) ký tự" : "\(builtinPreset.prompt.count) chars")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                                .cornerRadius(4)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Tab 4: Projects & Adaptive Self-Learning (Multi-Project Isolation + Glossary + TM)

    private var projectsTabContent: some View {
        let activeProj = storageManager.activeProject
        let projectItems = storageManager.items.filter { $0.projectId == activeProj.id }
        let verifiedCount = projectItems.filter { $0.isVerified }.count
        let pinnedCount = projectItems.filter { $0.isPinned }.count

        return VStack(spacing: 8) {
            // Card 1: Adaptive Learning Toggle & Project Selector / Creator
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isVi ? "Quản lý Dự án & Bộ nhớ Tự học AI" : "Projects & Adaptive AI Memory")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Toggle(isVi ? "Tự học theo Dự án" : "Adaptive Learning", isOn: Binding(
                        get: { storageManager.settings.enableAdaptiveLearning },
                        set: { val in
                            var s = storageManager.settings
                            s.enableAdaptiveLearning = val
                            storageManager.settings = s
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                }

                Text(isVi
                     ? "Mỗi Dự án có Lịch sử, Từ điển thuật ngữ và Bộ nhớ câu mẫu riêng biệt. Càng dịch, ghim hoặc sửa bản dịch trong dự án, AI càng hiểu rõ thuật ngữ và văn phong của dự án đó."
                     : "Each Project isolates its own History, Glossary, and Translation Memory. The more you translate, pin, or edit translations in a project, the smarter and more consistent AI becomes.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(isVi ? "Dự án đang chọn:" : "Active Project:")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(width: 110, alignment: .leading)

                    Picker("", selection: Binding<UUID>(
                        get: { activeProj.id },
                        set: { newId in
                            storageManager.selectActiveProject(id: newId)
                        }
                    )) {
                        ForEach(storageManager.projects) { proj in
                            Text(proj.name).tag(proj.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        renameProjectDraft = activeProj.name
                        showingRenameProjectPopover = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isVi ? "Đổi tên dự án đang chọn" : "Rename active project")
                    .popover(isPresented: $showingRenameProjectPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isVi ? "Đổi tên Dự án" : "Rename Project")
                                .font(.system(size: 12, weight: .semibold))
                            HStack(spacing: 6) {
                                TextField(isVi ? "Tên dự án..." : "Project name...", text: $renameProjectDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                                    .frame(width: 180)
                                    .onSubmit {
                                        let trimmed = renameProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            var updated = activeProj
                                            updated.name = trimmed
                                            storageManager.updateProject(updated)
                                        }
                                        showingRenameProjectPopover = false
                                    }
                                Button(isVi ? "Lưu" : "Save") {
                                    let trimmed = renameProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        var updated = activeProj
                                        updated.name = trimmed
                                        storageManager.updateProject(updated)
                                    }
                                    showingRenameProjectPopover = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(renameProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(10)
                    }

                    Button(action: {
                        duplicateActiveProject()
                    }) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isVi ? "Nhân bản dự án này (sao chép Ghi chú chuyên ngành & Từ điển thuật ngữ)" : "Duplicate this project (copies domain note & glossary)")

                    if activeProj.id != TranslationProject.defaultProjectId {
                        Button(role: .destructive) {
                            showingDeleteProjectConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(isVi ? "Xoá dự án này" : "Delete this project")
                        .confirmationDialog(
                            isVi ? "Xoá dự án \"\(activeProj.name)\"? Các bản dịch trong dự án sẽ được chuyển về dự án Mặc định." : "Delete project \"\(activeProj.name)\"? Its translations will be moved to the Default project.",
                            isPresented: $showingDeleteProjectConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(isVi ? "Xoá dự án" : "Delete Project", role: .destructive) {
                                storageManager.deleteProject(id: activeProj.id)
                            }
                            Button(isVi ? "Hủy" : "Cancel", role: .cancel) {}
                        }
                    }
                }

                HStack(spacing: 6) {
                    ZStack(alignment: .trailing) {
                        TextField(isVi ? "Tên dự án mới (VD: Dự án NHK, Ngân hàng, Game...)" : "New project name...", text: $newProjectNameInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit {
                                createNewProjectFromInput()
                            }

                        if !newProjectNameInput.isEmpty {
                            Button(action: { newProjectNameInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                        }
                    }

                    Button(isVi ? "+ Tạo Dự án" : "+ New Project") {
                        createNewProjectFromInput()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(newProjectNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)

            // Card 2: Project Context Note & Learning Stats
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(isVi ? "Ngữ cảnh riêng của Dự án \"\(activeProj.name)\"" : "Context for Project \"\(activeProj.name)\"")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    HStack(spacing: 8) {
                        Label("\(activeProj.glossary.count) \(isVi ? "thuật ngữ" : "terms")", systemImage: "book.closed")

                        Button(action: {
                            showingVerifiedExamplesPopover.toggle()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("\(verifiedCount) \(isVi ? "câu đã dạy" : "taught")")
                                    .underline()
                            }
                        }
                        .buttonStyle(.plain)
                        .help(isVi ? "Bấm để xem hoặc xoá các câu mẫu chuẩn đã dạy AI trong dự án này" : "Click to inspect or remove verified examples for this project")
                        .popover(isPresented: $showingVerifiedExamplesPopover, arrowEdge: .bottom) {
                            verifiedExamplesPopoverContent(for: activeProj)
                        }

                        Button(action: {
                            showingPinnedItemsPopover.toggle()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "pin.fill")
                                Text("\(pinnedCount) \(isVi ? "câu ghim" : "pinned")")
                                    .underline()
                            }
                        }
                        .buttonStyle(.plain)
                        .help(isVi ? "Bấm để xem, sao chép hoặc bỏ ghim các câu dịch đã ghim trong dự án này" : "Click to inspect, copy, or unpin pinned translations in this project")
                        .popover(isPresented: $showingPinnedItemsPopover, arrowEdge: .bottom) {
                            pinnedItemsPopoverContent(for: activeProj)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
                }

                HStack(spacing: 6) {
                    ZStack(alignment: .trailing) {
                        TextField(
                            isVi ? "Ghi chú chuyên ngành / văn phong cho dự án này (VD: Tài liệu y khoa, giữ nguyên tên thuốc)..." : "Domain / style guidelines for this project...",
                            text: Binding<String>(
                                get: { activeProj.domainNote },
                                set: { newNote in
                                    var updated = activeProj
                                    updated.domainNote = newNote
                                    storageManager.updateProject(updated)
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                        if !activeProj.domainNote.isEmpty {
                            Button(action: {
                                applyDomainNoteTemplate("")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                            .help(isVi ? "Xoá ghi chú ngữ cảnh" : "Clear domain note")
                        }
                    }

                    Menu(isVi ? "Mẫu gợi ý" : "Templates") {
                        Button(isVi ? "IT / Phần mềm (Giữ nguyên tên biến, API, thuật ngữ kỹ thuật)" : "IT / Software (Keep code, APIs, technical terms)") {
                            applyDomainNoteTemplate(isVi
                                ? "Tài liệu kỹ thuật phần mềm & IT. Giữ nguyên tên biến, hàm, API, câu lệnh CLI và thuật ngữ chuyên ngành phổ biến."
                                : "Software engineering & IT documentation. Preserve variable names, APIs, CLI commands, and standard technical terms.")
                        }
                        Button(isVi ? "Doanh nghiệp / BPO Nhật - Việt (Văn phong lịch sự, trang trọng)" : "Business / BPO (Polite, formal corporate tone)") {
                            applyDomainNoteTemplate(isVi
                                ? "Giao tiếp doanh nghiệp & BPO. Dịch lịch sự, rõ ràng, trang trọng, truyền tải chính xác kính ngữ và hạng mục công việc."
                                : "Corporate & BPO communication. Use a polite, formal, and clear tone, accurately conveying honorifics and action items.")
                        }
                        Button(isVi ? "Tài chính / Ngân hàng (Chuẩn thuật ngữ kế toán, ngân hàng)" : "Finance / Banking (Accurate financial & accounting terms)") {
                            applyDomainNoteTemplate(isVi
                                ? "Tài liệu tài chính, ngân hàng & kế toán. Sử dụng thuật ngữ tài chính chuẩn xác, nhất quán số liệu và đơn vị tiền tệ."
                                : "Financial, banking & accounting documents. Use precise financial terminology and keep figures/currencies consistent.")
                        }
                        Button(isVi ? "Y khoa / Dược phẩm (Giữ nguyên tên hoạt chất, thuật ngữ y học)" : "Medical / Pharma (Keep active ingredients & clinical terms)") {
                            applyDomainNoteTemplate(isVi
                                ? "Tài liệu y khoa & dược phẩm. Dịch chuẩn xác thuật ngữ lâm sàng, giữ nguyên tên quốc tế của thuốc và hoạt chất."
                                : "Medical & pharmaceutical documents. Translate clinical terms accurately and preserve international drug/ingredient names.")
                        }
                        if !activeProj.domainNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Divider()
                            Button(isVi ? "Xoá ghi chú ngữ cảnh" : "Clear Domain Note", role: .destructive) {
                                applyDomainNoteTemplate("")
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)

            // Card 3: Project Glossary (Từ điển Thuật ngữ của Dự án)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(isVi ? "Từ điển Thuật ngữ của Dự án" : "Project Glossary")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()

                    Button(action: pasteBulkGlossaryFromClipboard) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9.5))
                            Text(isVi ? "Dán nhanh" : "Paste")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(isVi ? "Dán nhiều cặp thuật ngữ từ Clipboard (mỗi dòng dạng: từ_gốc -> nghĩa_đích hoặc phân tách bằng Tab)" : "Paste multiple glossary pairs from Clipboard (one per line: source -> target or Tab-separated)")

                    Menu {
                        Button(isVi ? "Nhập từ điển từ tệp (.tsv / .csv / .txt)..." : "Import Glossary from File (.tsv / .csv / .txt)...") {
                            importGlossaryFromFilePanel()
                        }
                        if !activeProj.glossary.isEmpty {
                            Button(isVi ? "Xuất từ điển ra tệp (.tsv)..." : "Export Glossary to File (.tsv)...") {
                                exportGlossaryToFilePanel()
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 9.5))
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.mini)
                    .fixedSize()
                    .help(isVi ? "Nhập hoặc xuất từ điển thuật ngữ bằng tệp (.tsv / .csv / .txt)" : "Import or export glossary file (.tsv / .csv / .txt)")

                    if !activeProj.glossary.isEmpty {
                        Button(action: copyGlossaryToClipboard) {
                            HStack(spacing: 3) {
                                Image(systemName: didCopyGlossaryFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5))
                                Text(didCopyGlossaryFeedback ? (isVi ? "Đã chép" : "Copied") : (isVi ? "Sao chép" : "Copy"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(isVi ? "Sao chép toàn bộ từ điển thuật ngữ của dự án này vào Clipboard" : "Copy all glossary entries of this project to Clipboard")
                    }

                    if activeProj.glossary.count > 1 {
                        Button(action: {
                            var updated = activeProj
                            updated.glossary.sort {
                                $0.sourceTerm.localizedCaseInsensitiveCompare($1.sourceTerm) == .orderedAscending
                            }
                            storageManager.updateProject(updated)
                        }) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 9.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(isVi ? "Sắp xếp từ điển thuật ngữ theo thứ tự A–Z" : "Sort glossary terms alphabetically (A–Z)")

                        Button(action: { showingClearGlossaryConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5))
                                .foregroundColor(.red.opacity(0.85))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(isVi ? "Xoá toàn bộ từ điển thuật ngữ của dự án này" : "Clear all glossary entries of this project")
                        .confirmationDialog(
                            isVi ? "Xoá toàn bộ \(activeProj.glossary.count) thuật ngữ của dự án \"\(activeProj.name)\"?" : "Clear all \(activeProj.glossary.count) glossary terms in project \"\(activeProj.name)\"?",
                            isPresented: $showingClearGlossaryConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(isVi ? "Xoá toàn bộ từ điển" : "Clear All Terms", role: .destructive) {
                                var updated = activeProj
                                updated.glossary.removeAll()
                                storageManager.updateProject(updated)
                                glossarySearchQuery = ""
                            }
                            Button(isVi ? "Hủy" : "Cancel", role: .cancel) {}
                        }
                    }

                    if activeProj.glossary.count >= 3 {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                            TextField(isVi ? "Lọc thuật ngữ..." : "Filter terms...", text: $glossarySearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 10.5))
                                .frame(width: 115)
                            if !glossarySearchQuery.isEmpty {
                                Button(action: { glossarySearchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
                        )
                    }
                }

                HStack(spacing: 6) {
                    TextField(isVi ? "Từ / Cụm từ gốc (VD: 代表)" : "Source term", text: $newGlossarySourceInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    Button(action: {
                        let tmp = newGlossarySourceInput
                        newGlossarySourceInput = newGlossaryTargetInput
                        newGlossaryTargetInput = tmp
                    }) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isVi ? "Đảo chiều từ gốc và nghĩa chuẩn" : "Swap source and target terms")

                    TextField(isVi ? "Nghĩa chuẩn (VD: tổng đài)" : "Target term", text: $newGlossaryTargetInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit {
                            addGlossaryEntryFromInput()
                        }

                    if !newGlossarySourceInput.isEmpty || !newGlossaryTargetInput.isEmpty {
                        Button(action: {
                            newGlossarySourceInput = ""
                            newGlossaryTargetInput = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isVi ? "Xoá ô đang nhập" : "Clear input fields")
                    }

                    let trimmedSourceDraft = newGlossarySourceInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isUpdatingExistingTerm = !trimmedSourceDraft.isEmpty && activeProj.glossary.contains {
                        $0.sourceTerm.caseInsensitiveCompare(trimmedSourceDraft) == .orderedSame
                    }

                    Button(isUpdatingExistingTerm ? (isVi ? "Cập nhật" : "Update") : (isVi ? "Lưu" : "Save")) {
                        addGlossaryEntryFromInput()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(
                        trimmedSourceDraft.isEmpty ||
                        newGlossaryTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                let filteredGlossary: [GlossaryEntry] = {
                    let q = glossarySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !q.isEmpty else { return activeProj.glossary }
                    return activeProj.glossary.filter {
                        $0.sourceTerm.lowercased().contains(q) || $0.targetTerm.lowercased().contains(q)
                    }
                }()

                ScrollView {
                    if activeProj.glossary.isEmpty {
                        VStack(spacing: 4) {
                            Text(isVi
                                 ? "Chưa có thuật ngữ nào. Bạn có thể thêm tại đây hoặc bấm biểu tượng cây bút sửa trực tiếp ngay trên Popup dịch."
                                 : "No glossary terms yet. Add terms here or via the edit icon on the translation popup.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 18)
                        }
                        .frame(maxWidth: .infinity)
                    } else if filteredGlossary.isEmpty {
                        Text(isVi ? "Không tìm thấy thuật ngữ phù hợp." : "No matching glossary terms.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredGlossary) { entry in
                                HStack(spacing: 8) {
                                    Text(entry.sourceTerm)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)

                                    Text(entry.targetTerm)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.accentColor)
                                        .lineLimit(1)

                                    Spacer()

                                    Button(action: {
                                        let pairText = "\(entry.sourceTerm)\t\(entry.targetTerm)"
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(pairText, forType: .string)
                                        copiedGlossaryEntryId = entry.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            if copiedGlossaryEntryId == entry.id {
                                                copiedGlossaryEntryId = nil
                                            }
                                        }
                                    }) {
                                        Image(systemName: copiedGlossaryEntryId == entry.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(copiedGlossaryEntryId == entry.id ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isVi ? "Sao chép cặp thuật ngữ này" : "Copy this glossary pair")

                                    Button(action: {
                                        newGlossarySourceInput = entry.sourceTerm
                                        newGlossaryTargetInput = entry.targetTerm
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isVi ? "Sửa thuật ngữ này" : "Edit this glossary term")

                                    Button(action: {
                                        storageManager.removeGlossaryEntry(projectId: activeProj.id, entryId: entry.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .help(isVi ? "Xoá thuật ngữ này" : "Delete this glossary term")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                                .contextMenu {
                                    Button(isVi ? "Sửa thuật ngữ này" : "Edit Term") {
                                        newGlossarySourceInput = entry.sourceTerm
                                        newGlossaryTargetInput = entry.targetTerm
                                    }
                                    Button(isVi ? "Đảo chiều từ gốc & nghĩa chuẩn" : "Swap Source & Target") {
                                        var updated = activeProj
                                        if let idx = updated.glossary.firstIndex(where: { $0.id == entry.id }) {
                                            updated.glossary[idx] = GlossaryEntry(
                                                id: entry.id,
                                                sourceTerm: entry.targetTerm,
                                                targetTerm: entry.sourceTerm,
                                                createdAt: entry.createdAt
                                            )
                                            storageManager.updateProject(updated)
                                        }
                                    }
                                    Button(isVi ? "Sao chép cặp thuật ngữ" : "Copy Term Pair") {
                                        let pairText = "\(entry.sourceTerm)\t\(entry.targetTerm)"
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(pairText, forType: .string)
                                        copiedGlossaryEntryId = entry.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            if copiedGlossaryEntryId == entry.id {
                                                copiedGlossaryEntryId = nil
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(isVi ? "Xoá thuật ngữ" : "Delete Term", role: .destructive) {
                                        storageManager.removeGlossaryEntry(projectId: activeProj.id, entryId: entry.id)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }
                .frame(height: 118)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
    }

    private func createNewProjectFromInput() {
        let name = newProjectNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = storageManager.createProject(name: name)
        newProjectNameInput = ""
    }

    private func applyDomainNoteTemplate(_ note: String) {
        var updated = storageManager.activeProject
        updated.domainNote = note
        storageManager.updateProject(updated)
    }

    private func duplicateActiveProject() {
        let source = storageManager.activeProject
        let copySuffix = isVi ? " (Bản sao)" : " (Copy)"
        var created = storageManager.createProject(name: source.name + copySuffix, domainNote: source.domainNote)
        created.glossary = source.glossary.map { entry in
            GlossaryEntry(sourceTerm: entry.sourceTerm, targetTerm: entry.targetTerm)
        }
        storageManager.updateProject(created)
        storageManager.selectActiveProject(id: created.id)
    }

    private func addGlossaryEntryFromInput() {
        let src = newGlossarySourceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = newGlossaryTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !dst.isEmpty else { return }
        storageManager.addOrUpdateGlossaryEntry(
            projectId: storageManager.activeProject.id,
            sourceTerm: src,
            targetTerm: dst
        )
        newGlossarySourceInput = ""
        newGlossaryTargetInput = ""
    }

    private func pasteBulkGlossaryFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        importGlossaryRawString(raw)
    }

    private func importGlossaryRawString(_ raw: String) {
        let lines = raw.components(separatedBy: .newlines)
        let projId = storageManager.activeProject.id
        let separators = ["->", "=>", "\t", " = ", " : ", ","]
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            for sep in separators {
                if let range = trimmedLine.range(of: sep) {
                    let src = String(trimmedLine[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let dst = String(trimmedLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !src.isEmpty && !dst.isEmpty {
                        storageManager.addOrUpdateGlossaryEntry(projectId: projId, sourceTerm: src, targetTerm: dst)
                        break
                    }
                }
            }
        }
    }

    private func importGlossaryFromFilePanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .tabSeparatedText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        importGlossaryRawString(content)
    }

    private func exportGlossaryToFilePanel() {
        let proj = storageManager.activeProject
        guard !proj.glossary.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.nameFieldStringValue = "SuperTrans-Glossary-\(proj.name).tsv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatted = proj.glossary.map { "\($0.sourceTerm)\t\($0.targetTerm)" }.joined(separator: "\n")
        try? formatted.write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyGlossaryToClipboard() {
        let entries = storageManager.activeProject.glossary
        guard !entries.isEmpty else { return }
        let formatted = entries.map { "\($0.sourceTerm)\t\($0.targetTerm)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        didCopyGlossaryFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopyGlossaryFeedback = false
        }
    }

    private func moveAPIKey(at index: Int, offset: Int) {
        var keys = storageManager.settings.validAPIKeys
        let newIndex = index + offset
        guard index >= 0, index < keys.count, newIndex >= 0, newIndex < keys.count else { return }
        let item = keys.remove(at: index)
        keys.insert(item, at: newIndex)
        var s = storageManager.settings
        s.apiKeys = keys
        storageManager.settings = s
        keyRefreshTrigger = UUID()
    }

    private func verifiedExamplesPopoverContent(for project: TranslationProject) -> some View {
        let verifiedItems = storageManager.items.filter { $0.projectId == project.id && $0.isVerified }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text(isVi
                     ? "Câu mẫu chuẩn đã dạy AI — Dự án \"\(project.name)\""
                     : "Verified Gold Examples — Project \"\(project.name)\"")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("(\(verifiedItems.count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if !verifiedItems.isEmpty {
                    Button(action: {
                        let exported = verifiedItems.map { item in
                            if let src = item.sourceText, !src.isEmpty {
                                return "\(src)\t\(item.translatedText)"
                            }
                            return item.translatedText
                        }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exported, forType: .string)
                        didCopyAllPopoverItemsFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            didCopyAllPopoverItemsFeedback = false
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: didCopyAllPopoverItemsFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(didCopyAllPopoverItemsFeedback ? (isVi ? "Đã chép" : "Copied") : (isVi ? "Chép tất cả" : "Copy All"))
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(isVi ? "Sao chép toàn bộ câu mẫu chuẩn của dự án vào Clipboard" : "Copy all verified examples in this project to Clipboard")
                }

                if verifiedItems.count > 1 {
                    Button(action: {
                        for item in verifiedItems {
                            storageManager.setTranslationVerified(id: item.id, isVerified: false)
                        }
                    }) {
                        Text(isVi ? "Gỡ tất cả" : "Clear All")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(isVi ? "Gỡ bỏ toàn bộ câu mẫu chuẩn trong dự án này" : "Remove all verified examples in this project")
                }
            }

            if verifiedItems.isEmpty {
                Text(isVi
                     ? "Chưa có câu mẫu chuẩn nào trong dự án này. Khi dịch văn bản trên Popup, hãy bấm biểu tượng cây bút để sửa và lưu bản dịch chuẩn cho AI học."
                     : "No verified examples in this project yet. Click the pencil icon on the translation popup to edit and teach AI a verified translation.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(verifiedItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let src = item.sourceText, !src.isEmpty {
                                        Text(src)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(item.translatedText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.translatedText, forType: .string)
                                    copiedPopoverItemId = item.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        if copiedPopoverItemId == item.id {
                                            copiedPopoverItemId = nil
                                        }
                                    }
                                }) {
                                    Image(systemName: copiedPopoverItemId == item.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(copiedPopoverItemId == item.id ? .green : .secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.borderless)
                                .help(isVi ? "Sao chép bản dịch chuẩn" : "Copy verified translation")

                                Button(action: {
                                    storageManager.setTranslationVerified(id: item.id, isVerified: false)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.red.opacity(0.85))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.borderless)
                                .help(isVi ? "Gỡ bỏ câu mẫu này khỏi bộ nhớ ưu tiên của AI" : "Remove from Verified Gold Examples")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 370)
    }

    private func pinnedItemsPopoverContent(for project: TranslationProject) -> some View {
        let pinnedItems = storageManager.items.filter { $0.projectId == project.id && $0.isPinned }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text(isVi
                     ? "Bản dịch đã ghim — Dự án \"\(project.name)\""
                     : "Pinned Translations — Project \"\(project.name)\"")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("(\(pinnedItems.count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if !pinnedItems.isEmpty {
                    Button(action: {
                        let exported = pinnedItems.map { item in
                            if let src = item.sourceText, !src.isEmpty {
                                return "\(src)\t\(item.translatedText)"
                            }
                            return item.translatedText
                        }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exported, forType: .string)
                        didCopyAllPopoverItemsFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            didCopyAllPopoverItemsFeedback = false
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: didCopyAllPopoverItemsFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(didCopyAllPopoverItemsFeedback ? (isVi ? "Đã chép" : "Copied") : (isVi ? "Chép tất cả" : "Copy All"))
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(isVi ? "Sao chép toàn bộ bản dịch đã ghim của dự án vào Clipboard" : "Copy all pinned translations in this project to Clipboard")
                }

                if pinnedItems.count > 1 {
                    Button(action: {
                        for item in pinnedItems where item.isPinned {
                            storageManager.togglePin(id: item.id)
                        }
                    }) {
                        Text(isVi ? "Bỏ ghim tất cả" : "Unpin All")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(isVi ? "Bỏ ghim toàn bộ các câu dịch trong dự án này" : "Unpin all translations in this project")
                }
            }

            if pinnedItems.isEmpty {
                Text(isVi
                     ? "Chưa có bản dịch nào được ghim trong dự án này. Bấm biểu tượng ghim trên Popup hoặc trong Lịch sử để lưu các câu dịch quan trọng."
                     : "No pinned translations in this project yet. Click the pin icon on the popup or in History to keep important translations.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(pinnedItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let src = item.sourceText, !src.isEmpty {
                                        Text(src)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(item.translatedText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.translatedText, forType: .string)
                                    copiedPopoverItemId = item.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        if copiedPopoverItemId == item.id {
                                            copiedPopoverItemId = nil
                                        }
                                    }
                                }) {
                                    Image(systemName: copiedPopoverItemId == item.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(copiedPopoverItemId == item.id ? .green : .secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.borderless)
                                .help(isVi ? "Sao chép bản dịch" : "Copy translation")

                                Button(action: {
                                    storageManager.togglePin(id: item.id)
                                }) {
                                    Image(systemName: "pin.slash")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.orange)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.borderless)
                                .help(isVi ? "Bỏ ghim bản dịch này" : "Unpin this translation")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 370)
    }

    private func pasteAndAddKeyFromClipboard() {
        guard let clipStr = NSPasteboard.general.string(forType: .string) else { return }
        let parts = clipStr
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }

        var s = storageManager.settings
        for key in parts {
            if !s.apiKeys.contains(key) {
                s.apiKeys.append(key)
            }
        }
        storageManager.settings = s
        newAPIKeyInput = ""
        keyRefreshTrigger = UUID()
    }

    private func addKeysFromInput() {
        let parts = newAPIKeyInput
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }

        var s = storageManager.settings
        for key in parts {
            if !s.apiKeys.contains(key) {
                s.apiKeys.append(key)
            }
        }
        storageManager.settings = s
        newAPIKeyInput = ""
        keyRefreshTrigger = UUID()
    }

    private func removeKey(_ key: String) {
        var s = storageManager.settings
        s.apiKeys.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines) == key }
        storageManager.settings = s
        APIKeyRotator.shared.clearState(for: key)
        keyRefreshTrigger = UUID()
    }

    private func testSingleKey(_ key: String) {
        testingKeys.insert(key)
        let model = storageManager.settings.selectedModel
        Task {
            _ = await GeminiClient.shared.testAPIKey(key, model: model)
            await MainActor.run {
                testingKeys.remove(key)
                keyRefreshTrigger = UUID()
            }
        }
    }

    private func testSelectedModel() {
        guard let firstKey = storageManager.settings.validAPIKeys.first else { return }
        let model = storageManager.settings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        isTestingSelectedModel = true
        selectedModelTestStatus = nil
        Task {
            let result = await GeminiClient.shared.testAPIKey(firstKey, model: model)
            let ok: Bool
            if case .success = result {
                ok = true
            } else {
                ok = false
            }
            await MainActor.run {
                isTestingSelectedModel = false
                selectedModelTestStatus = ok
                keyRefreshTrigger = UUID()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if selectedModelTestStatus == ok {
                        selectedModelTestStatus = nil
                    }
                }
            }
        }
    }

    private func testAllAPIKeys() {
        let keys = storageManager.settings.validAPIKeys
        guard !keys.isEmpty else { return }
        isTestingAllKeys = true
        let model = storageManager.settings.selectedModel
        Task {
            for key in keys {
                _ = await GeminiClient.shared.testAPIKey(key, model: model)
            }
            await MainActor.run {
                isTestingAllKeys = false
                keyRefreshTrigger = UUID()
            }
        }
    }

    // MARK: - Tab 3: Ignored Apps (SuperClip Exact Layout)

    private var ignoredAppsTabContent: some View {
        let ignoredCount = storageManager.settings.ignoredApps.count
        let ignoredBids = Set(storageManager.settings.ignoredApps.map { $0.bundleIdentifier.lowercased() })
        let selfBundleId = Bundle.main.bundleIdentifier?.lowercased() ?? "com.nhanqv.supertrans"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(loc.tr(.tabIgnoredApps))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(isVi ? "(\(ignoredCount) ứng dụng)" : "(\(ignoredCount) apps)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(loc.tr(.ignoredAppsDescription))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)

            if storageManager.settings.ignoredApps.isEmpty {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text(loc.tr(.noIgnoredApps))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Button(action: {
                                let presets: [(name: String, bid: String)] = [
                                    ("Keychain Access", "com.apple.keychainaccess"),
                                    ("1Password", "com.1password.1password"),
                                    ("Bitwarden", "com.bitwarden.desktop"),
                                    ("KeePassXC", "org.keepassxc.keepassxc"),
                                    ("Terminal", "com.apple.Terminal"),
                                    ("iTerm2", "com.googlecode.iterm2")
                                ]
                                for p in presets {
                                    let iconPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bid)?.path
                                    storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: p.bid, name: p.name, iconPath: iconPath))
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 10.5))
                                    Text(isVi ? "Thêm nhanh trình quản lý mật khẩu & Terminal" : "Add Password Managers & Terminals")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                    )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(storageManager.settings.ignoredApps) { app in
                            ignoredAppRow(app)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            }

            HStack(spacing: 8) {
                Button(action: openAppSelectionPanel) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isVi ? "Chọn ứng dụng từ thư mục Applications" : "Choose app from Applications folder")

                Button(action: removeSelectedIgnoredApp) {
                    Image(systemName: "minus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedIgnoredAppId == nil)
                .help(isVi ? "Bỏ chặn ứng dụng đang chọn" : "Remove selected ignored app")

                Menu(loc.tr(.addRunningAppButton)) {
                    let runningApps = NSWorkspace.shared.runningApplications
                        .filter {
                            $0.activationPolicy == .regular &&
                            $0.bundleIdentifier != nil &&
                            $0.bundleIdentifier?.lowercased() != selfBundleId
                        }
                        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

                    ForEach(runningApps, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier, let name = app.localizedName {
                            let isAlreadyIgnored = ignoredBids.contains(bid.lowercased())
                            Button(isAlreadyIgnored ? "\(name) (\(isVi ? "Đã thêm" : "Added"))" : "\(name) (\(bid))") {
                                storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: bid, name: name, iconPath: app.bundleURL?.path))
                            }
                            .disabled(isAlreadyIgnored)
                        }
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()

                Menu(isVi ? "Gợi ý bảo mật" : "Security Presets") {
                    let presets: [(name: String, bid: String)] = [
                        ("Keychain Access", "com.apple.keychainaccess"),
                        ("1Password", "com.1password.1password"),
                        ("Bitwarden", "com.bitwarden.desktop"),
                        ("KeePassXC", "org.keepassxc.keepassxc"),
                        ("Terminal", "com.apple.Terminal"),
                        ("iTerm2", "com.googlecode.iterm2")
                    ]
                    let unaddedPresets = presets.filter { !ignoredBids.contains($0.bid.lowercased()) }

                    if !unaddedPresets.isEmpty {
                        Button(isVi ? "Thêm tất cả trình quản lý mật khẩu & Terminal" : "Add All Password Managers & Terminals") {
                            for p in unaddedPresets {
                                let iconPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bid)?.path
                                storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: p.bid, name: p.name, iconPath: iconPath))
                            }
                        }
                        Divider()
                    }

                    ForEach(presets, id: \.bid) { preset in
                        let isAlreadyIgnored = ignoredBids.contains(preset.bid.lowercased())
                        Button(isAlreadyIgnored ? "\(preset.name) (\(isVi ? "Đã thêm" : "Added"))" : "\(preset.name) (\(preset.bid))") {
                            let iconPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preset.bid)?.path
                            storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: preset.bid, name: preset.name, iconPath: iconPath))
                        }
                        .disabled(isAlreadyIgnored)
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
                .help(isVi ? "Thêm nhanh các trình quản lý mật khẩu và Terminal phổ biến vào danh sách bỏ qua" : "Quickly add common password managers and terminals to the ignored list")

                Spacer()

                if !storageManager.settings.ignoredApps.isEmpty {
                    Button(action: {
                        if storageManager.settings.ignoredApps.count > 1 {
                            showingClearIgnoredAppsConfirmation = true
                        } else {
                            var s = storageManager.settings
                            s.ignoredApps.removeAll()
                            storageManager.settings = s
                            selectedIgnoredAppId = nil
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text(isVi ? "Bỏ chặn tất cả" : "Clear All")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        isVi ? "Bỏ chặn toàn bộ \(storageManager.settings.ignoredApps.count) ứng dụng trong danh sách?" : "Remove all \(storageManager.settings.ignoredApps.count) apps from the ignored list?",
                        isPresented: $showingClearIgnoredAppsConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(isVi ? "Bỏ chặn tất cả" : "Clear All", role: .destructive) {
                            var s = storageManager.settings
                            s.ignoredApps.removeAll()
                            storageManager.settings = s
                            selectedIgnoredAppId = nil
                        }
                        Button(isVi ? "Hủy" : "Cancel", role: .cancel) {}
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func ignoredAppRow(_ app: IgnoredApp) -> some View {
        let isSelected = selectedIgnoredAppId == app.id
        return HStack(spacing: 8) {
            appIconImage(for: app)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text(app.name.isEmpty ? app.bundleIdentifier : app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text(app.bundleIdentifier)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if !app.bundleIdentifier.isEmpty {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.bundleIdentifier, forType: .string)
                    copiedIgnoredAppBid = app.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedIgnoredAppBid == app.id {
                            copiedIgnoredAppBid = nil
                        }
                    }
                }) {
                    Image(systemName: copiedIgnoredAppBid == app.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5))
                        .foregroundColor(copiedIgnoredAppBid == app.id ? .green : .secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isVi ? "Sao chép Bundle ID (\(app.bundleIdentifier))" : "Copy Bundle ID (\(app.bundleIdentifier))")
            }

            if let path = app.iconPath ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)?.path,
               FileManager.default.fileExists(atPath: path) {
                Button(action: {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isVi ? "Hiển thị ứng dụng trong Finder" : "Reveal app in Finder")
            }

            Button(action: {
                storageManager.removeIgnoredApp(bundleIdentifier: app.bundleIdentifier.isEmpty ? app.name : app.bundleIdentifier)
                if selectedIgnoredAppId == app.id {
                    selectedIgnoredAppId = nil
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isVi ? "Bỏ chặn ứng dụng này" : "Remove this ignored app")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIgnoredAppId = app.id
        }
        .contextMenu {
            if let path = app.iconPath ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)?.path,
               FileManager.default.fileExists(atPath: path) {
                Button(isVi ? "Hiển thị trong Finder" : "Reveal in Finder") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
            if !app.bundleIdentifier.isEmpty {
                Button(isVi ? "Sao chép Bundle ID" : "Copy Bundle ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.bundleIdentifier, forType: .string)
                    copiedIgnoredAppBid = app.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedIgnoredAppBid == app.id {
                            copiedIgnoredAppBid = nil
                        }
                    }
                }
            }
            Divider()
            Button(isVi ? "Bỏ chặn ứng dụng này" : "Remove Ignored App", role: .destructive) {
                storageManager.removeIgnoredApp(bundleIdentifier: app.bundleIdentifier.isEmpty ? app.name : app.bundleIdentifier)
                if selectedIgnoredAppId == app.id {
                    selectedIgnoredAppId = nil
                }
            }
        }
    }

    private func appIconImage(for app: IgnoredApp) -> Image {
        if let path = app.iconPath, FileManager.default.fileExists(atPath: path) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(nsImage: NSWorkspace.shared.icon(for: .application))
    }

    private func openAppSelectionPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle, .application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                let bundle = Bundle(url: url)
                let bid = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
                let name = FileManager.default.displayName(atPath: url.path)
                storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: bid, name: name, iconPath: url.path))
            }
        }
    }

    private func removeSelectedIgnoredApp() {
        guard let id = selectedIgnoredAppId else { return }
        if let match = storageManager.settings.ignoredApps.first(where: { $0.id == id }) {
            storageManager.removeIgnoredApp(bundleIdentifier: match.bundleIdentifier.isEmpty ? match.name : match.bundleIdentifier)
        }
        selectedIgnoredAppId = nil
    }

    // MARK: - Tab 4: About & Storage Management (SuperClip Style)

    private var aboutTabContent: some View {
        VStack(spacing: 8) {
            // Storage Summary Card
            VStack(alignment: .leading, spacing: 8) {
                Text(isVi ? "Quản lý dữ liệu lịch sử" : "History Data Management")
                    .font(.system(size: 12.5, weight: .semibold))

                VStack(spacing: 5) {
                    metricRow(label: isVi ? "Tổng số bản dịch đang lưu" : "Total Stored Translations", value: "\(storageManager.items.count)")
                    metricRow(label: isVi ? "Bản dịch đã ghim / Mẫu chuẩn đã dạy" : "Pinned / Verified Examples", value: "\(storageManager.items.filter { $0.isPinned }.count) / \(storageManager.items.filter { $0.isVerified }.count)")
                    metricRow(label: isVi ? "Số Dự án & Thuật ngữ từ điển" : "Projects & Glossary Terms", value: "\(storageManager.projects.count) \(isVi ? "dự án" : "projects") · \(storageManager.projects.reduce(0) { $0 + $1.glossary.count }) \(isVi ? "từ" : "terms")")
                    metricRow(label: isVi ? "Dung lượng sử dụng" : "Disk Space Used", value: calculateDiskUsageFormatted())
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)

                let unpinnedCount = storageManager.items.filter { !$0.isPinned }.count

                HStack(spacing: 10) {
                    Button(action: { showingClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text(unpinnedCount > 0 ? "\(loc.tr(.clearUnpinnedHistory)) (\(unpinnedCount))" : loc.tr(.clearUnpinnedHistory))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(unpinnedCount == 0)
                    .confirmationDialog(
                        isVi ? "Xóa toàn bộ \(unpinnedCount) lịch sử chưa ghim?" : "Clear all \(unpinnedCount) unpinned history items?",
                        isPresented: $showingClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(loc.tr(.clearUnpinnedHistory), role: .destructive) {
                            storageManager.clearUnpinnedHistory()
                        }
                        Button(isVi ? "Hủy" : "Cancel", role: .cancel) {}
                    }

                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageManager.baseDirectory.path)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(isVi ? "Mở thư mục lưu trữ" : "Open in Finder")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    if let statusMsg = backupStatusMessage {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(statusMsg)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }

                    Menu(isVi ? "Sao lưu & Khôi phục" : "Backup & Restore") {
                        Button(isVi ? "Xuất bản sao lưu cấu hình & dự án (.json)..." : "Export Settings & Projects Backup (.json)...") {
                            exportBackupPanel()
                        }
                        Button(isVi ? "Nhập bản sao lưu cấu hình & dự án (.json)..." : "Import Settings & Projects Backup (.json)...") {
                            importBackupPanel()
                        }
                        Divider()
                        Button(isVi ? "Khôi phục cài đặt gốc..." : "Reset Preferences to Default...", role: .destructive) {
                            showingResetConfirmation = true
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .fixedSize()
                    .confirmationDialog(
                        isVi ? "Khôi phục các tuỳ chọn cài đặt về mặc định? (API Key, Dự án và Lịch sử dịch vẫn được giữ nguyên)" : "Reset preferences to default? (Your API Keys, Projects, and Translation History will be preserved)",
                        isPresented: $showingResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(isVi ? "Khôi phục cài đặt gốc" : "Reset Preferences", role: .destructive) {
                            resetPreferencesPreservingUserData()
                        }
                        Button(isVi ? "Hủy" : "Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)

            // About Card
            VStack(spacing: 10) {
                SuperTransBrandIcon(size: 48)

                VStack(spacing: 2) {
                    Text("SuperTrans")
                        .font(.system(size: 15, weight: .bold))
                    HStack(spacing: 5) {
                        Text("Version \(updateManager.currentVersion) (com.nhanqv.supertrans)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: {
                            let info = "SuperTrans v\(updateManager.currentVersion) (com.nhanqv.supertrans) — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info, forType: .string)
                            didCopyVersionInfoFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                didCopyVersionInfoFeedback = false
                            }
                        }) {
                            Image(systemName: didCopyVersionInfoFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9.5))
                                .foregroundColor(didCopyVersionInfoFeedback ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isVi ? "Sao chép thông tin phiên bản" : "Copy version info")
                    }
                }

                // Check for Updates Section (SuperClip style)
                VStack(spacing: 8) {
                    Button(action: {
                        updateManager.checkForUpdates(userInitiated: true)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .medium))
                            Text(isVi ? "Kiểm tra cập nhật" : "Check for Updates")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updateManager.isBusy)

                    updateStatusView
                }

                Divider()

                HStack {
                    Text("GitHub:")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        if let url = URL(string: "https://github.com/nhanqv-ai/SuperTrans") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("nhanqv-ai/SuperTrans")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    Text("·")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                    Button(action: {
                        if let url = URL(string: "https://github.com/nhanqv-ai/SuperTrans/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text(isVi ? "Nhật ký phiên bản" : "Releases")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(isVi ? "Đang kiểm tra bản cập nhật..." : "Checking for updates...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .upToDate(let currentVer):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text(isVi ? "Bạn đang dùng phiên bản mới nhất (\(currentVer))" : "You're up to date (\(currentVer))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }
        case .updateAvailable(let release):
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 12))
                    Text(isVi ? "Có phiên bản mới: \(release.versionString)" : "New version available: \(release.versionString)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                }

                if release.zipAssetURL != nil {
                    Button(action: {
                        updateManager.startDownloadAndInstall(release: release)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 10, weight: .semibold))
                            Text(isVi ? "Cập nhật ngay" : "Update Now")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(action: {
                        NSWorkspace.shared.open(release.htmlURL)
                    }) {
                        Text(isVi ? "Tải từ GitHub" : "Download from GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(6)
        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(isVi ? "Đang tải về và chuẩn bị cài đặt (\(Int(progress * 100))%)..." : "Downloading & preparing update (\(Int(progress * 100))%)...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        case .readyToRestart(let release):
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(isVi ? "Đã tải xong \(release.tagName) — Khởi động lại để hoàn tất" : "\(release.tagName) ready — Restart to apply")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }

                Button(action: {
                    updateManager.restartApp()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isVi ? "Khởi động lại" : "Restart Now")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(6)
        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func calculateDiskUsageFormatted() -> String {
        let url = storageManager.baseDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true,
               let sz = vals.fileSize {
                totalBytes += Int64(sz)
            }
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: totalBytes)
    }

    private func resetPreferencesPreservingUserData() {
        let current = storageManager.settings
        var fresh = AppSettings()
        fresh.apiKeys = current.apiKeys
        fresh.customPromptPresets = current.customPromptPresets
        fresh.activeProjectId = current.activeProjectId
        storageManager.settings = fresh
    }

    private struct SuperTransBackupPayload: Codable {
        var exportedAt: Date
        var settings: AppSettings
        var projects: [TranslationProject]
    }

    private func exportBackupPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "SuperTrans-Backup-\(formatter.string(from: Date())).json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        let payload = SuperTransBackupPayload(
            exportedAt: Date(),
            settings: storageManager.settings,
            projects: storageManager.projects
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(payload) {
            try? data.write(to: targetURL, options: .atomic)
            showBackupStatus(isVi ? "Đã xuất sao lưu" : "Backup exported")
        }
    }

    private func importBackupPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let sourceURL = panel.url,
              let data = try? Data(contentsOf: sourceURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let payload = try? dec.decode(SuperTransBackupPayload.self, from: data) {
            storageManager.mergeOrRestoreProjects(payload.projects)
            storageManager.settings = payload.settings
            keyRefreshTrigger = UUID()
            showBackupStatus(isVi ? "Đã khôi phục" : "Backup restored")
        } else if let settingsOnly = try? dec.decode(AppSettings.self, from: data) {
            storageManager.settings = settingsOnly
            keyRefreshTrigger = UUID()
            showBackupStatus(isVi ? "Đã khôi phục" : "Backup restored")
        }
    }

    private func showBackupStatus(_ message: String) {
        backupStatusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if backupStatusMessage == message {
                backupStatusMessage = nil
            }
        }
    }

    // MARK: - Footer Bar

    private var activePromptShortTitle: String {
        let s = storageManager.settings
        let activeId = s.resolvedActivePromptId
        if let builtin = AppSettings.promptPresets.first(where: { $0.id == activeId }) {
            return isVi ? builtin.shortTitleVi : builtin.shortTitleEn
        }
        if let custom = s.customPromptPresets.first(where: { $0.id.uuidString == activeId }) {
            let trimmed = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? (isVi ? "Prompt tuỳ chỉnh" : "Custom Prompt") : trimmed
        }
        return isVi ? "Mặc định" : "Default"
    }

    private var footerBar: some View {
        let keyCount = storageManager.settings.validAPIKeys.count
        let activeProjName = storageManager.activeProject.name

        return HStack(spacing: 10) {
            Menu {
                ForEach(AppSettings.presetModels, id: \.self) { preset in
                    let isSelected = storageManager.settings.selectedModel == preset && !isCustomModelMode
                    Button(isSelected ? "✓ \(preset)" : preset) {
                        isCustomModelMode = false
                        selectedModelTestStatus = nil
                        var s = storageManager.settings
                        s.selectedModel = preset
                        storageManager.settings = s
                    }
                }
                Divider()
                Button(isVi ? "Dán & Thêm API Key từ Clipboard" : "Paste & Add API Key from Clipboard") {
                    pasteAndAddKeyFromClipboard()
                }
                if keyCount > 0 {
                    Button(isVi ? "Kiểm tra tất cả Key" : "Test All Keys") {
                        testAllAPIKeys()
                    }
                    Button(isVi ? "Đặt lại trạng thái Key" : "Reset Key Cooldowns") {
                        APIKeyRotator.shared.clearState()
                        keyRefreshTrigger = UUID()
                    }
                }
                Divider()
                Button(isVi ? "Quản lý Gemini AI..." : "Manage Gemini AI...") {
                    stopShortcutRecording()
                    selectedTab = .geminiAI
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(keyCount > 0 ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(keyCount > 0
                         ? "\(keyCount) API Key"
                         : (isVi ? "Chưa có Key" : "No API Key"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(keyCount > 0 ? .secondary : .orange)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isVi ? "Đổi nhanh Model Gemini, kiểm tra Key hoặc mở tab Gemini AI" : "Quickly switch Gemini Model, test keys, or open Gemini AI tab")

            Text("·")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.6))

            Menu {
                ForEach(storageManager.projects) { proj in
                    Button(proj.id == storageManager.activeProject.id ? "✓ \(proj.name)" : proj.name) {
                        storageManager.selectActiveProject(id: proj.id)
                    }
                }
                Divider()
                Button(isVi ? "Quản lý Dự án..." : "Manage Projects...") {
                    stopShortcutRecording()
                    selectedTab = .projects
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 9.5))
                    Text(activeProjName)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isVi ? "Đổi nhanh Dự án đang chọn hoặc mở tab Dự án" : "Quickly switch Active Project or open Projects tab")

            Text("·")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.6))

            Menu {
                let s = storageManager.settings
                let activeId = s.resolvedActivePromptId
                ForEach(s.visibleBuiltinPromptPresets) { preset in
                    let title = isVi ? preset.shortTitleVi : preset.shortTitleEn
                    Button(preset.id == activeId ? "✓ \(title)" : title) {
                        var updated = storageManager.settings
                        updated.selectedPromptId = preset.id
                        updated.customSystemPrompt = preset.prompt
                        storageManager.settings = updated
                    }
                }
                if !s.visibleCustomPromptPresets.isEmpty {
                    Divider()
                    ForEach(s.visibleCustomPromptPresets) { custom in
                        let title = custom.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? (isVi ? "Prompt tuỳ chỉnh" : "Custom Prompt")
                            : custom.name
                        Button(custom.id.uuidString == activeId ? "✓ \(title)" : title) {
                            var updated = storageManager.settings
                            updated.selectedPromptId = custom.id.uuidString
                            updated.customSystemPrompt = custom.prompt
                            storageManager.settings = updated
                        }
                    }
                }
                Divider()
                Button(isVi ? "Quản lý Prompt..." : "Manage Prompts...") {
                    stopShortcutRecording()
                    selectedTab = .prompt
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9.5))
                    Text(activePromptShortTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isVi ? "Đổi nhanh Prompt đang dùng hoặc mở tab Prompt" : "Quickly switch Active Prompt or open Prompt tab")

            Spacer()

            Button(isVi ? "Xong" : "Done") {
                onDismiss?()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Shortcut Recording

    private func startShortcutRecording(forTranslate: Bool) {
        stopShortcutRecording()
        isRecordingTranslateShortcut = forTranslate
        isRecordingHistoryShortcut = !forTranslate

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopShortcutRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return nil }

            let mods = HotKeyManager.carbonModifiers(from: flags)
            let code = UInt32(event.keyCode)

            var s = storageManager.settings
            if forTranslate {
                s.translateHotKeyKeyCode = code
                s.translateHotKeyModifiers = mods
            } else {
                s.historyHotKeyKeyCode = code
                s.historyHotKeyModifiers = mods
            }
            storageManager.settings = s
            stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        isRecordingTranslateShortcut = false
        isRecordingHistoryShortcut = false
        if let monitor = shortcutEventMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutEventMonitor = nil
        }
    }
}
