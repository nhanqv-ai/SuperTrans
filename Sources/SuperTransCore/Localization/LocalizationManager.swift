import Foundation
import Combine

public enum LKey: String, CaseIterable, Sendable {
    // App & Menu
    case appName
    case showTranslationHistory
    case translateClipboardNow
    case autoTranslateOnCopy
    case preferences
    case clearUnpinnedHistory
    case quitApp

    // History Panel
    case searchPlaceholder
    case pinnedSection
    case recentSection
    case emptyHistoryTitle
    case emptyHistorySubtitle
    case noSearchResultsTitle
    case noSearchResultsSubtitle
    case preferencesTooltip
    case dismissTooltip
    case imageTag
    case imageTagBare
    case originalLabel
    case translatedLabel
    case modelLabel

    // Row Context Menu & Tooltips
    case pinItem
    case unpinItem
    case maskItem
    case revealItem
    case copyTranslation
    case copyOriginal
    case retranslateItem
    case openInPopup
    case deleteItem

    // Cursor Translation Popup
    case popupTranslating
    case popupTargetLanguage
    case popupCopyTranslation
    case popupCopied
    case popupAutoPaste
    case popupRetranslate
    case popupPinTooltip
    case popupCloseTooltip
    case popupShowOriginal
    case popupHideOriginal
    case popupConfigureAPIKey
    case popupRetry

    // Errors
    case errorMissingAPIKey
    case errorEmptyInput
    case errorAllKeysRateLimited
    case errorInvalidAPIKey
    case errorEmptyResponse

    // Settings Tabs
    case tabGeneral
    case tabGeminiAI
    case tabShortcuts
    case tabIgnoredApps

    // Settings - General
    case generalStartupSection
    case launchAtLogin
    case recordTranslationHistory
    case autoPasteOnSelection
    case accessibilityPermissionTitle
    case accessibilityTrusted
    case accessibilityUntrusted
    case grantPermissionButton
    case triggerModeSection
    case enableDoubleCopyTrigger
    case enableDoubleCopySubtitle
    case enableAutoTranslateEveryCopy
    case enableAutoTranslateSubtitle
    case defaultTargetLanguageLabel
    case uiLanguageLabel
    case historyCapacityLabel
    case displayCapacityLabel

    // Settings - Gemini AI
    case geminiAPIKeysSection
    case geminiAPIKeysSubtitle
    case addAPIKeyPlaceholder
    case addAPIKeyButton
    case bulkAddKeysButton
    case testAllKeysButton
    case clearCooldownsButton
    case keyStatusActive
    case keyStatusReady
    case keyStatusRateLimited
    case keyStatusInvalid
    case testSingleKeyButton
    case removeKeyButton
    case noAPIKeysConfigured
    case geminiModelSection
    case selectModelLabel
    case customModelPlaceholder
    case systemPromptSection
    case systemPromptSubtitle
    case resetDefaultPromptButton

    // Settings - Shortcuts
    case translateShortcutSection
    case translateShortcutDesc
    case historyShortcutSection
    case historyShortcutDesc
    case pressShortcutPrompt
    case recordShortcutButton
    case resetDefaultShortcutButton

    // Settings - Ignored Apps
    case ignoredAppsDescription
    case addRunningAppButton
    case addBundleIdPlaceholder
    case removeIgnoredAppButton
    case noIgnoredApps
}

public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()

    private let lock = NSLock()
    private var _languageCode: String = "vi"

    public var languageCode: String {
        lock.lock()
        defer { lock.unlock() }
        return _languageCode
    }

    public init() {}

    public func setLanguage(code: String) {
        let resolved: String
        if code == "system" {
            let sys = Locale.preferredLanguages.first?.lowercased() ?? "vi"
            resolved = sys.hasPrefix("vi") ? "vi" : "en"
        } else {
            resolved = code
        }
        lock.lock()
        let changed = (_languageCode != resolved)
        _languageCode = resolved
        lock.unlock()

        if changed {
            if Thread.isMainThread {
                self.objectWillChange.send()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
        }
    }

    public func tr(_ key: LKey) -> String {
        let lang = languageCode
        if lang == "en" {
            return Self.enStrings[key] ?? key.rawValue
        }
        return Self.viStrings[key] ?? Self.enStrings[key] ?? key.rawValue
    }

    private static let viStrings: [LKey: String] = [
        .appName: "SuperTrans",
        .showTranslationHistory: "Lịch sử dịch thuật",
        .translateClipboardNow: "Dịch nội dung đang chọn / Clipboard (Option+T)",
        .autoTranslateOnCopy: "Tự động dịch mọi lần Copy (Cmd+C)",
        .preferences: "Cài đặt...",
        .clearUnpinnedHistory: "Xóa lịch sử chưa ghim",
        .quitApp: "Thoát SuperTrans",

        .searchPlaceholder: "Tìm kiếm bản dịch hoặc nội dung gốc...",
        .pinnedSection: "ĐÃ GHIM",
        .recentSection: "LỊCH SỬ DỊCH GẦN ĐÂY",
        .emptyHistoryTitle: "Chưa có lịch sử dịch",
        .emptyHistorySubtitle: "Nhấn Option+T hoặc Cmd+C 2 lần để dịch văn bản và hình ảnh",
        .noSearchResultsTitle: "Không tìm thấy kết quả phù hợp",
        .noSearchResultsSubtitle: "Thử tìm với từ khóa khác",
        .preferencesTooltip: "Mở Cài đặt (Cmd+,)",
        .dismissTooltip: "Đóng cửa sổ (Esc)",
        .imageTag: "[Ảnh]",
        .imageTagBare: "Ảnh chụp",
        .originalLabel: "NỘI DUNG GỐC",
        .translatedLabel: "BẢN DỊCH",
        .modelLabel: "Model",

        .pinItem: "Ghim bản dịch",
        .unpinItem: "Bỏ ghim",
        .maskItem: "Ẩn nội dung nhạy cảm",
        .revealItem: "Hiện nội dung",
        .copyTranslation: "Sao chép bản dịch",
        .copyOriginal: "Sao chép nội dung gốc",
        .retranslateItem: "Dịch lại mục này",
        .openInPopup: "Xem trên cửa sổ Popup",
        .deleteItem: "Xóa mục này",

        .popupTranslating: "Đang dịch bằng Gemini AI...",
        .popupTargetLanguage: "Dịch sang",
        .popupCopyTranslation: "Copy",
        .popupCopied: "Đã copy!",
        .popupAutoPaste: "Dán đè (Cmd+Enter)",
        .popupRetranslate: "Dịch lại",
        .popupPinTooltip: "Ghim cửa sổ nổi không tự đóng",
        .popupCloseTooltip: "Đóng (Esc)",
        .popupShowOriginal: "Xem nội dung gốc",
        .popupHideOriginal: "Thu gọn nội dung gốc",
        .popupConfigureAPIKey: "Cài đặt Gemini API Key...",
        .popupRetry: "Thử lại",

        .errorMissingAPIKey: "Chưa cấu hình Gemini API Key. Vui lòng thêm API Key trong phần Cài đặt.",
        .errorEmptyInput: "Không có nội dung văn bản hoặc hình ảnh để dịch.",
        .errorAllKeysRateLimited: "Tất cả Gemini API Key đều đang chạm giới hạn (Rate Limit 429)",
        .errorInvalidAPIKey: "Gemini API Key không hợp lệ hoặc bị từ chối",
        .errorEmptyResponse: "Gemini không trả về kết quả dịch.",

        .tabGeneral: "Chung",
        .tabGeminiAI: "Gemini AI",
        .tabShortcuts: "Phím tắt",
        .tabIgnoredApps: "Ứng dụng bỏ qua",

        .generalStartupSection: "Hệ thống & Hành vi",
        .launchAtLogin: "Khởi động cùng macOS",
        .recordTranslationHistory: "Lưu lịch sử các bản dịch",
        .autoPasteOnSelection: "Tự động dán (Direct Auto-Paste) khi chọn bản dịch",
        .accessibilityPermissionTitle: "Quyền Trợ năng (Cần cho lấy vùng chọn & Auto-Paste):",
        .accessibilityTrusted: "Đã cấp quyền",
        .accessibilityUntrusted: "Chưa cấp quyền",
        .grantPermissionButton: "Cấp quyền...",
        .triggerModeSection: "Cơ chế kích hoạt dịch",
        .enableDoubleCopyTrigger: "Nhấn Cmd + C 2 lần liên tiếp (Double Copy) để dịch nhanh",
        .enableDoubleCopySubtitle: "Khi đang bôi đen văn bản hoặc copy ảnh, nhấn Cmd+C 2 lần trong 0.4 giây sẽ bật Popup dịch ngay phía trên con trỏ chuột",
        .enableAutoTranslateEveryCopy: "Tự động dịch mọi thao tác Copy (Cmd + C)",
        .enableAutoTranslateSubtitle: "Tự động bật Popup dịch ngay mỗi khi clipboard thay đổi (hữu ích khi đang đọc tài liệu ngoại ngữ liên tục)",
        .defaultTargetLanguageLabel: "Ngôn ngữ đích mặc định:",
        .uiLanguageLabel: "Ngôn ngữ giao diện:",
        .historyCapacityLabel: "Số lượng lưu tối đa:",
        .displayCapacityLabel: "Số mục hiển thị nhanh:",

        .geminiAPIKeysSection: "Danh sách Gemini API Key (Tự động xoay vòng)",
        .geminiAPIKeysSubtitle: "Nhập nhiều API Key để tự động chuyển đổi luân phiên và vượt giới hạn Rate Limit (HTTP 429) của gói miễn phí.",
        .addAPIKeyPlaceholder: "Dán một hoặc nhiều Gemini API Key (cách nhau bởi dấu phẩy hoặc xuống dòng)...",
        .addAPIKeyButton: "Thêm Key",
        .bulkAddKeysButton: "Thêm",
        .testAllKeysButton: "Kiểm tra tất cả Key",
        .clearCooldownsButton: "Đặt lại trạng thái",
        .keyStatusActive: "Đang dùng tốt",
        .keyStatusReady: "Sẵn sàng",
        .keyStatusRateLimited: "Đang chờ hồi quota",
        .keyStatusInvalid: "Key lỗi",
        .testSingleKeyButton: "Kiểm tra",
        .removeKeyButton: "Xóa",
        .noAPIKeysConfigured: "Chưa có API Key nào. Hãy lấy key tại aistudio.google.com và thêm vào trên.",
        .geminiModelSection: "Cấu hình Model Gemini",
        .selectModelLabel: "Model sử dụng:",
        .customModelPlaceholder: "Nhập tên model Gemini (vd: gemini-2.5-flash)",
        .systemPromptSection: "System Prompt (Hướng dẫn dịch)",
        .systemPromptSubtitle: "Tùy chỉnh phong cách dịch thuật của Gemini AI.",
        .resetDefaultPromptButton: "Khôi phục mặc định",

        .translateShortcutSection: "Phím tắt Dịch nhanh (Vùng đang chọn / Clipboard)",
        .translateShortcutDesc: "Nhấn tổ hợp phím này ở bất kỳ đâu để tự động lấy văn bản đang bôi đen (hoặc ảnh/văn bản trong clipboard) và hiện Popup dịch ngay phía trên con trỏ chuột.",
        .historyShortcutSection: "Phím tắt Mở nhanh Lịch sử dịch tại vị trí chuột",
        .historyShortcutDesc: "Mở cửa sổ nổi danh sách lịch sử các bản dịch ngay cạnh con trỏ chuột.",
        .pressShortcutPrompt: "Nhấn tổ hợp phím mới...",
        .recordShortcutButton: "Đổi phím tắt",
        .resetDefaultShortcutButton: "Mặc định",

        .ignoredAppsDescription: "Không tự động kích hoạt dịch khi sao chép từ các ứng dụng trong danh sách này (ví dụ: trình quản lý mật khẩu, Terminal...).",
        .addRunningAppButton: "Thêm từ ứng dụng đang chạy",
        .addBundleIdPlaceholder: "Nhập Bundle ID hoặc tên ứng dụng...",
        .removeIgnoredAppButton: "Xóa",
        .noIgnoredApps: "Chưa có ứng dụng nào trong danh sách bỏ qua."
    ]

    private static let enStrings: [LKey: String] = [
        .appName: "SuperTrans",
        .showTranslationHistory: "Show Translation History",
        .translateClipboardNow: "Translate Selection / Clipboard (Option+T)",
        .autoTranslateOnCopy: "Auto-Translate Every Copy (Cmd+C)",
        .preferences: "Preferences...",
        .clearUnpinnedHistory: "Clear Unpinned History",
        .quitApp: "Quit SuperTrans",

        .searchPlaceholder: "Search translations or original text...",
        .pinnedSection: "PINNED",
        .recentSection: "RECENT TRANSLATIONS",
        .emptyHistoryTitle: "No translations yet",
        .emptyHistorySubtitle: "Press Option+T or Double Cmd+C to translate text and images",
        .noSearchResultsTitle: "No matching translations",
        .noSearchResultsSubtitle: "Try a different search query",
        .preferencesTooltip: "Open Preferences (Cmd+,)",
        .dismissTooltip: "Dismiss (Esc)",
        .imageTag: "[Image]",
        .imageTagBare: "Image",
        .originalLabel: "ORIGINAL",
        .translatedLabel: "TRANSLATION",
        .modelLabel: "Model",

        .pinItem: "Pin Translation",
        .unpinItem: "Unpin Translation",
        .maskItem: "Mask Sensitive Info",
        .revealItem: "Reveal Content",
        .copyTranslation: "Copy Translation",
        .copyOriginal: "Copy Original Text",
        .retranslateItem: "Re-translate",
        .openInPopup: "Open in Translation Popup",
        .deleteItem: "Delete Item",

        .popupTranslating: "Translating with Gemini AI...",
        .popupTargetLanguage: "Translate to",
        .popupCopyTranslation: "Copy",
        .popupCopied: "Copied!",
        .popupAutoPaste: "Auto-Paste (Cmd+Enter)",
        .popupRetranslate: "Re-translate",
        .popupPinTooltip: "Pin popup to keep on top",
        .popupCloseTooltip: "Close (Esc)",
        .popupShowOriginal: "Show original content",
        .popupHideOriginal: "Hide original content",
        .popupConfigureAPIKey: "Configure Gemini API Key...",
        .popupRetry: "Retry",

        .errorMissingAPIKey: "No Gemini API Key configured. Please add your API Key in Preferences.",
        .errorEmptyInput: "No text or image found to translate.",
        .errorAllKeysRateLimited: "All configured Gemini API Keys hit rate limits (HTTP 429)",
        .errorInvalidAPIKey: "Invalid or unauthorized Gemini API Key",
        .errorEmptyResponse: "Gemini returned an empty translation response.",

        .tabGeneral: "General",
        .tabGeminiAI: "Gemini AI",
        .tabShortcuts: "Shortcuts",
        .tabIgnoredApps: "Ignored Apps",

        .generalStartupSection: "System & Behavior",
        .launchAtLogin: "Launch at login",
        .recordTranslationHistory: "Save translation history",
        .autoPasteOnSelection: "Direct Auto-Paste when selecting a translation",
        .accessibilityPermissionTitle: "Accessibility Permission (Selection grab & Auto-Paste):",
        .accessibilityTrusted: "Granted",
        .accessibilityUntrusted: "Not Granted",
        .grantPermissionButton: "Grant Permission...",
        .triggerModeSection: "Translation Triggers",
        .enableDoubleCopyTrigger: "Press Cmd + C twice quickly (Double Copy) to translate",
        .enableDoubleCopySubtitle: "Pressing Cmd+C twice within 0.4s automatically opens the translation popup above your cursor",
        .enableAutoTranslateEveryCopy: "Auto-translate every Copy (Cmd + C)",
        .enableAutoTranslateSubtitle: "Automatically translate and show popup whenever clipboard content changes",
        .defaultTargetLanguageLabel: "Default Target Language:",
        .uiLanguageLabel: "Interface Language:",
        .historyCapacityLabel: "Max History Capacity:",
        .displayCapacityLabel: "Recent Display Count:",

        .geminiAPIKeysSection: "Gemini API Keys (Automatic Key Rotation)",
        .geminiAPIKeysSubtitle: "Add multiple API keys to automatically rotate and bypass free-tier rate limits (HTTP 429).",
        .addAPIKeyPlaceholder: "Paste one or more Gemini API Keys (comma or newline separated)...",
        .addAPIKeyButton: "Add Key",
        .bulkAddKeysButton: "Add",
        .testAllKeysButton: "Test All Keys",
        .clearCooldownsButton: "Reset Status",
        .keyStatusActive: "Active",
        .keyStatusReady: "Ready",
        .keyStatusRateLimited: "Rate Limited",
        .keyStatusInvalid: "Invalid",
        .testSingleKeyButton: "Test",
        .removeKeyButton: "Remove",
        .noAPIKeysConfigured: "No API Keys configured yet. Get your key at aistudio.google.com.",
        .geminiModelSection: "Gemini Model Configuration",
        .selectModelLabel: "Model:",
        .customModelPlaceholder: "Enter Gemini model ID (e.g. gemini-2.5-flash)",
        .systemPromptSection: "System Prompt (Translation Instructions)",
        .systemPromptSubtitle: "Customize how Gemini AI translates your content.",
        .resetDefaultPromptButton: "Reset to Default",

        .translateShortcutSection: "Quick Translate Shortcut (Selection / Clipboard)",
        .translateShortcutDesc: "Press anywhere to grab selected text (or current clipboard text/image) and display the translation popup right above your mouse cursor.",
        .historyShortcutSection: "Floating Translation History Shortcut",
        .historyShortcutDesc: "Summon the floating translation history panel near your mouse cursor.",
        .pressShortcutPrompt: "Press new shortcut...",
        .recordShortcutButton: "Record Shortcut",
        .resetDefaultShortcutButton: "Reset Default",

        .ignoredAppsDescription: "Do not auto-translate when copying from these applications (e.g. Password Managers, Terminal...).",
        .addRunningAppButton: "Add from Running Apps",
        .addBundleIdPlaceholder: "Enter Bundle ID or App Name...",
        .removeIgnoredAppButton: "Remove",
        .noIgnoredApps: "No ignored applications configured."
    ]
}
