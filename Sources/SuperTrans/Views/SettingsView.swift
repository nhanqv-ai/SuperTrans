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
        case ignoredApps
        case about

        public var id: String { rawValue }

        public var title: String {
            let isVi = LocalizationManager.shared.languageCode == "vi"
            switch self {
            case .general: return LocalizationManager.shared.tr(.tabGeneral)
            case .geminiAI: return LocalizationManager.shared.tr(.tabGeminiAI)
            case .ignoredApps: return LocalizationManager.shared.tr(.tabIgnoredApps)
            case .about: return isVi ? "Thông tin" : "About"
            }
        }

        public var iconName: String {
            switch self {
            case .general: return "gear"
            case .geminiAI: return "sparkles"
            case .ignoredApps: return "eye.slash"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .general
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    // MARK: - Top Tab Bar (SuperClip Style — Zero Animation for Instant Response)

    private var topTabBar: some View {
        HStack(spacing: 18) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: {
                    stopShortcutRecording()
                    selectedTab = tab
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 10)
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
        .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc.tr(.geminiAPIKeysSection))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("(\(storageManager.settings.validAPIKeys.count) keys)")
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
                    .frame(height: 86)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "key")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                            Text(loc.tr(.noAPIKeysConfigured))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
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
                .frame(height: 102)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
                .id(keyRefreshTrigger)

                HStack(spacing: 8) {
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

                    Spacer()
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func apiKeyRow(index: Int, key: String) -> some View {
        let isRevealed = revealedKeys.contains(key)
        let isTesting = testingKeys.contains(key)
        let status = APIKeyRotator.shared.status(for: key)

        return HStack(spacing: 6) {
            Text("#\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .leading)

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
                removeKey(key)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10.5))
                    .foregroundColor(.red)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
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
        case .rateLimited:
            HStack(spacing: 3) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text(loc.tr(.keyStatusRateLimited)).font(.system(size: 10, weight: .medium)).foregroundColor(.orange)
            }
        case .invalid:
            HStack(spacing: 3) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(loc.tr(.keyStatusInvalid)).font(.system(size: 10, weight: .medium)).foregroundColor(.red)
            }
        }
    }

    private var modelAndPromptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.tr(.geminiModelSection))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)

            // Fast Preset Buttons (Instant click response)
            HStack(spacing: 6) {
                ForEach(AppSettings.presetModels, id: \.self) { preset in
                    let isSelected = storageManager.settings.selectedModel == preset
                    Button(action: {
                        var s = storageManager.settings
                        s.selectedModel = preset
                        storageManager.settings = s
                    }) {
                        Text(preset)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 0.8)
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Text("Model ID:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(loc.tr(.customModelPlaceholder), text: Binding(
                    get: { storageManager.settings.selectedModel },
                    set: { val in
                        var s = storageManager.settings
                        s.selectedModel = val
                        storageManager.settings = s
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text(loc.tr(.systemPromptSection))
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button(loc.tr(.resetDefaultPromptButton)) {
                    var s = storageManager.settings
                    s.customSystemPrompt = AppSettings.defaultSystemPrompt
                    storageManager.settings = s
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(size: 10))
            }

            TextEditor(text: Binding(
                get: { storageManager.settings.customSystemPrompt },
                set: { val in
                    var s = storageManager.settings
                    s.customSystemPrompt = val
                    storageManager.settings = s
                }
            ))
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 68)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
            )
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.tr(.tabIgnoredApps))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text(loc.tr(.ignoredAppsDescription))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)

            if storageManager.settings.ignoredApps.isEmpty {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text(loc.tr(.noIgnoredApps))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
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

                Button(action: removeSelectedIgnoredApp) {
                    Image(systemName: "minus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedIgnoredAppId == nil)

                Menu(loc.tr(.addRunningAppButton)) {
                    let runningApps = NSWorkspace.shared.runningApplications.filter {
                        $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                    }
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier, let name = app.localizedName {
                            Button("\(name) (\(bid))") {
                                storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: bid, name: name, iconPath: app.bundleURL?.path))
                            }
                        }
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()

                Spacer()
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
                    metricRow(label: isVi ? "Bản dịch đã ghim" : "Pinned Translations", value: "\(storageManager.items.filter { $0.isPinned }.count)")
                    metricRow(label: isVi ? "Dung lượng sử dụng" : "Disk Space Used", value: calculateDiskUsageFormatted())
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)

                HStack(spacing: 10) {
                    Button(action: { showingClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text(loc.tr(.clearUnpinnedHistory))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        isVi ? "Xóa toàn bộ lịch sử chưa ghim?" : "Clear all unpinned history?",
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
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)

            // About Card
            VStack(spacing: 10) {
                if let appIcon = NSApp?.applicationIconImage, appIcon.isValid {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 2) {
                    Text("SuperTrans")
                        .font(.system(size: 15, weight: .bold))
                    Text("Version \(updateManager.currentVersion) (com.nhanqv.supertrans)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Spacer()
            Button(isVi ? "Xong" : "Done") {
                onDismiss?()
            }
            .keyboardShortcut(.defaultAction)
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
