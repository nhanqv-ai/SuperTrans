import SwiftUI
import AppKit
import Carbon
import SuperTransCore

public struct SettingsView: View {
    @ObservedObject public var storageManager: StorageManager
    @ObservedObject private var loc = LocalizationManager.shared
    public let hotKeyManager: any HotKeyManaging
    public let autoPasteService: any AutoPasteServicing

    @State private var selectedTab: Int = 0
    @State private var newAPIKeyInput: String = ""
    @State private var revealedKeys: Set<String> = []
    @State private var testingKeys: Set<String> = []
    @State private var isTestingAllKeys: Bool = false
    @State private var keyRefreshTrigger: UUID = UUID()
    @State private var isRecordingTranslateShortcut: Bool = false
    @State private var isRecordingHistoryShortcut: Bool = false
    @State private var shortcutEventMonitor: Any? = nil
    @State private var customBundleIdInput: String = ""
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    public init(
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared
    ) {
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.autoPasteService = autoPasteService
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(loc.tr(.tabGeneral), systemImage: "gearshape")
                }
                .tag(0)

            geminiTab
                .tabItem {
                    Label(loc.tr(.tabGeminiAI), systemImage: "sparkles")
                }
                .tag(1)

            shortcutsTab
                .tabItem {
                    Label(loc.tr(.tabShortcuts), systemImage: "keyboard")
                }
                .tag(2)

            ignoredAppsTab
                .tabItem {
                    Label(loc.tr(.tabIgnoredApps), systemImage: "eye.slash")
                }
                .tag(3)
        }
        .padding(16)
        .frame(width: 640, height: 540)
        .onAppear {
            isAccessibilityTrusted = autoPasteService.checkAccessibilityPermission()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    // MARK: - Tab 1: General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trigger Modes Group
                GroupBox(label: Label(loc.tr(.triggerModeSection), systemImage: "bolt.circle")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { storageManager.settings.enableDoubleCopyTrigger },
                            set: { val in
                                var s = storageManager.settings
                                s.enableDoubleCopyTrigger = val
                                storageManager.settings = s
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.tr(.enableDoubleCopyTrigger))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(loc.tr(.enableDoubleCopySubtitle))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        Toggle(isOn: Binding(
                            get: { storageManager.settings.autoTranslateEveryCopy },
                            set: { val in
                                var s = storageManager.settings
                                s.autoTranslateEveryCopy = val
                                storageManager.settings = s
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.tr(.enableAutoTranslateEveryCopy))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(loc.tr(.enableAutoTranslateSubtitle))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                // Languages & Capacity Group
                GroupBox(label: Label(loc.tr(.generalStartupSection), systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(loc.tr(.defaultTargetLanguageLabel))
                                .frame(width: 190, alignment: .leading)
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
                            .frame(maxWidth: 260)
                        }

                        HStack {
                            Text(loc.tr(.uiLanguageLabel))
                                .frame(width: 190, alignment: .leading)
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
                            .frame(maxWidth: 260)
                        }

                        HStack {
                            Text(loc.tr(.historyCapacityLabel))
                                .frame(width: 190, alignment: .leading)
                            Stepper(
                                value: Binding(
                                    get: { storageManager.settings.capacity },
                                    set: { val in
                                        var s = storageManager.settings
                                        s.capacity = max(10, min(1000, val))
                                        storageManager.settings = s
                                    }
                                ),
                                in: 10...1000,
                                step: 10
                            ) {
                                Text("\(storageManager.settings.capacity)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                        }

                        Divider()

                        Toggle(loc.tr(.launchAtLogin), isOn: Binding(
                            get: { storageManager.settings.launchAtLogin },
                            set: { val in
                                var s = storageManager.settings
                                s.launchAtLogin = val
                                storageManager.settings = s
                                LaunchAtLoginManager.shared.setEnabled(val)
                            }
                        ))

                        Toggle(loc.tr(.recordTranslationHistory), isOn: Binding(
                            get: { storageManager.settings.recordHistory },
                            set: { val in
                                var s = storageManager.settings
                                s.recordHistory = val
                                storageManager.settings = s
                            }
                        ))

                        Toggle(loc.tr(.autoPasteOnSelection), isOn: Binding(
                            get: { storageManager.settings.autoPasteOnSelection },
                            set: { val in
                                var s = storageManager.settings
                                s.autoPasteOnSelection = val
                                storageManager.settings = s
                            }
                        ))

                        HStack(spacing: 8) {
                            Text(loc.tr(.accessibilityPermissionTitle))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Image(systemName: isAccessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isAccessibilityTrusted ? .green : .orange)
                            Text(isAccessibilityTrusted ? loc.tr(.accessibilityTrusted) : loc.tr(.accessibilityUntrusted))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isAccessibilityTrusted ? .green : .orange)
                            Spacer()
                            Button(loc.tr(.grantPermissionButton)) {
                                isAccessibilityTrusted = autoPasteService.resetAndRequestAccessibilityPermission()
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Tab 2: Gemini AI (Multi-Key Rotation, Model, System Prompt)

    private var geminiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Multi-API Key Rotation Section
                GroupBox(label: Label(loc.tr(.geminiAPIKeysSection), systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.tr(.geminiAPIKeysSubtitle))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            TextField(loc.tr(.addAPIKeyPlaceholder), text: $newAPIKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit {
                                    addKeysFromInput()
                                }

                            Button(action: addKeysFromInput) {
                                Label(loc.tr(.addAPIKeyButton), systemImage: "plus")
                            }
                            .disabled(newAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if storageManager.settings.validAPIKeys.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                Text(loc.tr(.noAPIKeysConfigured))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            HStack {
                                Text("Tổng số Key: \(storageManager.settings.validAPIKeys.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    APIKeyRotator.shared.clearState()
                                    keyRefreshTrigger = UUID()
                                }) {
                                    Text(loc.tr(.clearCooldownsButton))
                                        .font(.system(size: 11))
                                }
                                Button(action: testAllAPIKeys) {
                                    HStack(spacing: 4) {
                                        if isTestingAllKeys {
                                            ProgressView().controlSize(.mini)
                                        }
                                        Text(loc.tr(.testAllKeysButton))
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                }
                                .disabled(isTestingAllKeys)
                            }

                            VStack(spacing: 4) {
                                ForEach(Array(storageManager.settings.validAPIKeys.enumerated()), id: \.offset) { idx, key in
                                    apiKeyRow(index: idx, key: key)
                                }
                            }
                            .id(keyRefreshTrigger)
                        }
                    }
                    .padding(8)
                }

                // 2. Gemini Model Section
                GroupBox(label: Label(loc.tr(.geminiModelSection), systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(loc.tr(.selectModelLabel))
                                .font(.system(size: 12))
                            ForEach(AppSettings.presetModels, id: \.self) { preset in
                                Button(action: {
                                    var s = storageManager.settings
                                    s.selectedModel = preset
                                    storageManager.settings = s
                                }) {
                                    Text(preset)
                                        .font(.system(size: 11, weight: storageManager.settings.selectedModel == preset ? .bold : .regular, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(storageManager.settings.selectedModel == preset ? Color.accentColor : Color.secondary.opacity(0.14))
                                        )
                                        .foregroundColor(storageManager.settings.selectedModel == preset ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
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
                            .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .padding(8)
                }

                // 3. System Prompt Section
                GroupBox(label: Label(loc.tr(.systemPromptSection), systemImage: "text.bubble")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(loc.tr(.systemPromptSubtitle))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(loc.tr(.resetDefaultPromptButton)) {
                                var s = storageManager.settings
                                s.customSystemPrompt = AppSettings.defaultSystemPrompt
                                storageManager.settings = s
                            }
                            .font(.system(size: 11))
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
                        .frame(height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                        )
                    }
                    .padding(8)
                }
            }
            .padding(4)
        }
    }

    private func apiKeyRow(index: Int, key: String) -> some View {
        let isRevealed = revealedKeys.contains(key)
        let isTesting = testingKeys.contains(key)
        let status = APIKeyRotator.shared.status(for: key)

        return HStack(spacing: 8) {
            Text("#\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .leading)

            Text(isRevealed ? key : APIKeyRotator.maskKey(key))
                .font(.system(size: 11, design: .monospaced))
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
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Button(action: {
                testSingleKey(key)
            }) {
                if isTesting {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(loc.tr(.testSingleKeyButton))
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .disabled(isTesting)

            Button(action: {
                removeKey(key)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
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

    // MARK: - Tab 3: Shortcuts

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label(loc.tr(.translateShortcutSection), systemImage: "sparkles")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(loc.tr(.translateShortcutDesc))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text(isRecordingTranslateShortcut
                             ? loc.tr(.pressShortcutPrompt)
                             : HotKeyManager.formatShortcut(
                                keyCode: storageManager.settings.translateHotKeyKeyCode,
                                modifiers: storageManager.settings.translateHotKeyModifiers
                             ))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isRecordingTranslateShortcut ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                            )

                        Button(loc.tr(.recordShortcutButton)) {
                            startShortcutRecording(forTranslate: true)
                        }

                        Button(loc.tr(.resetDefaultShortcutButton)) {
                            stopShortcutRecording()
                            var s = storageManager.settings
                            s.translateHotKeyKeyCode = AppSettings.defaultTranslateHotKeyKeyCode
                            s.translateHotKeyModifiers = AppSettings.defaultTranslateHotKeyModifiers
                            storageManager.settings = s
                        }
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label(loc.tr(.historyShortcutSection), systemImage: "clock.arrow.circlepath")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(loc.tr(.historyShortcutDesc))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text(isRecordingHistoryShortcut
                             ? loc.tr(.pressShortcutPrompt)
                             : HotKeyManager.formatShortcut(
                                keyCode: storageManager.settings.historyHotKeyKeyCode,
                                modifiers: storageManager.settings.historyHotKeyModifiers
                             ))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isRecordingHistoryShortcut ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                            )

                        Button(loc.tr(.recordShortcutButton)) {
                            startShortcutRecording(forTranslate: false)
                        }

                        Button(loc.tr(.resetDefaultShortcutButton)) {
                            stopShortcutRecording()
                            var s = storageManager.settings
                            s.historyHotKeyKeyCode = AppSettings.defaultHistoryHotKeyKeyCode
                            s.historyHotKeyModifiers = AppSettings.defaultHistoryHotKeyModifiers
                            storageManager.settings = s
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(4)
    }

    private func startShortcutRecording(forTranslate: Bool) {
        stopShortcutRecording()
        isRecordingTranslateShortcut = forTranslate
        isRecordingHistoryShortcut = !forTranslate

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels recording
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

    // MARK: - Tab 4: Ignored Apps

    private var ignoredAppsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.tr(.ignoredAppsDescription))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField(loc.tr(.addBundleIdPlaceholder), text: $customBundleIdInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addCustomIgnoredApp()
                    }

                Button(loc.tr(.bulkAddKeysButton)) {
                    addCustomIgnoredApp()
                }
                .disabled(customBundleIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Menu(loc.tr(.addRunningAppButton)) {
                    let runningApps = NSWorkspace.shared.runningApplications.filter {
                        $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                    }
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier, let name = app.localizedName {
                            Button("\(name) (\(bid))") {
                                storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: bid, name: name))
                            }
                        }
                    }
                }
                .fixedSize()
            }

            if storageManager.settings.ignoredApps.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text(loc.tr(.noIgnoredApps))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    ForEach(storageManager.settings.ignoredApps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name.isEmpty ? app.bundleIdentifier : app.name)
                                    .font(.system(size: 12, weight: .medium))
                                if !app.bundleIdentifier.isEmpty {
                                    Text(app.bundleIdentifier)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(loc.tr(.removeIgnoredAppButton)) {
                                storageManager.removeIgnoredApp(bundleIdentifier: app.bundleIdentifier.isEmpty ? app.name : app.bundleIdentifier)
                            }
                        }
                    }
                }
            }
        }
        .padding(4)
    }

    private func addCustomIgnoredApp() {
        let trimmed = customBundleIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storageManager.addIgnoredApp(IgnoredApp(bundleIdentifier: trimmed, name: trimmed))
        customBundleIdInput = ""
    }
}
