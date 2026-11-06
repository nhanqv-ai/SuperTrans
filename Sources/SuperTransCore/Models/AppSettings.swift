import Foundation

public struct PromptPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let shortTitleVi: String
    public let shortTitleEn: String
    public let titleVi: String
    public let titleEn: String
    public let prompt: String

    public init(
        id: String,
        shortTitleVi: String,
        shortTitleEn: String,
        titleVi: String,
        titleEn: String,
        prompt: String
    ) {
        self.id = id
        self.shortTitleVi = shortTitleVi
        self.shortTitleEn = shortTitleEn
        self.titleVi = titleVi
        self.titleEn = titleEn
        self.prompt = prompt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var apiKeys: [String]
    public var selectedModel: String
    public var customSystemPrompt: String
    public var targetLanguage: String
    public var enableDoubleCopyTrigger: Bool
    public var autoTranslateEveryCopy: Bool
    public var translateHotKeyKeyCode: UInt32
    public var translateHotKeyModifiers: UInt32
    public var historyHotKeyKeyCode: UInt32
    public var historyHotKeyModifiers: UInt32
    public var autoPasteOnSelection: Bool
    public var recordHistory: Bool
    public var capacity: Int
    public var displayCapacity: Int
    public var pollIntervalMs: Int
    public var maxThumbnailPixelSize: Int
    public var launchAtLogin: Bool
    public var language: String
    public var ignoredApps: [IgnoredApp]
    public var automaticallyCheckForUpdates: Bool
    public var lastUpdateCheckDate: Date?
    public var popupWidth: Double?
    public var popupHeight: Double?

    public static let defaultModel: String = "gemini-3.1-flash-lite"
    public static let presetModels: [String] = [
        "gemini-3.1-flash-lite",
        "gemini-3.5-flash-lite",
        "gemini-3-flash-preview",
        "gemini-3.5-flash"
    ]

    public static let defaultSystemPrompt: String = """
You are a professional, accurate personal translator. Translate the user's input naturally and accurately into the requested target language.
Rules:
1. Return ONLY the translated text without introductory remarks, explanations, or quotes around the entire text.
2. Preserve original formatting, line breaks, bullet points, and code/technical identifiers where appropriate.
3. If the input is an image, extract all visible text in the image and translate it naturally into the target language while maintaining its structure.
"""

    public static let promptPresets: [PromptPreset] = [
        PromptPreset(
            id: "default",
            shortTitleVi: "Mặc định (Tự nhiên)",
            shortTitleEn: "Default (Natural)",
            titleVi: "Mặc định — Dịch tự nhiên & chuẩn xác",
            titleEn: "Default — Natural & Accurate Translation",
            prompt: AppSettings.defaultSystemPrompt
        ),
        PromptPreset(
            id: "it_tech",
            shortTitleVi: "IT / Phần mềm",
            shortTitleEn: "IT / Software",
            titleVi: "Chuyên ngành IT / Phần mềm — Giữ nguyên thuật ngữ & Code",
            titleEn: "IT & Software Engineering — Preserve Technical Terms & Code",
            prompt: """
You are a senior software engineer and technical translator. Translate the user's input accurately into the requested target language.
Rules:
1. Return ONLY the translated text without introductory remarks or explanations.
2. Keep programming keywords, variable/function names, CLI commands, API paths, log identifiers, and standard English IT terms (e.g., commit, pull request, deploy, payload, token, thread) intact where appropriate.
3. Preserve all code blocks, markdown formatting, bullet points, and line breaks.
4. If the input is an image (screenshot of code, logs, or UI), extract all visible text and translate naturally while preserving technical structure.
"""
        ),
        PromptPreset(
            id: "business",
            shortTitleVi: "Email / Công việc",
            shortTitleEn: "Business / BPO",
            titleVi: "Email & Công việc (BPO/Doanh nghiệp) — Văn phong lịch sự, chuyên nghiệp",
            titleEn: "Business & BPO Communication — Polite & Professional Tone",
            prompt: """
You are an executive business and BPO communication translator (experienced with Japanese, English, and Vietnamese corporate workflows). Translate the user's input into the requested target language using a polite, clear, and professional business tone.
Rules:
1. Return ONLY the translated text without extra commentary.
2. Accurately convey honorifics, nuances, action items, deadlines, and client/partner names.
3. Preserve original bullet points, numbering, and paragraph structure.
4. If the input is an image (document, chat log, or spreadsheet screenshot), extract all visible text and translate accurately in structured form.
"""
        ),
        PromptPreset(
            id: "learning",
            shortTitleVi: "Học ngoại ngữ (Giải thích)",
            shortTitleEn: "Language Learning",
            titleVi: "Học ngoại ngữ — Dịch kèm giải thích từ vựng & cấu trúc câu",
            titleEn: "Language Learning — Translate with Vocabulary & Grammar Notes",
            prompt: """
Translate the user's input into the requested target language and provide brief language-learning notes.
Format your response as follows:
1. [Bản dịch / Translation]: Natural and accurate translation of the input.
2. [Từ vựng & Ngữ pháp / Key Vocabulary & Grammar]: 2-4 bullet points explaining key words, idioms, or grammar structures from the source text.
"""
        ),
        PromptPreset(
            id: "concise",
            shortTitleVi: "Tóm tắt ý chính",
            shortTitleEn: "Concise Summary",
            titleVi: "Tóm tắt & Dịch ý chính ngắn gọn",
            titleEn: "Concise Summary & Core Meaning Translation",
            prompt: """
Translate the user's input into the requested target language concisely, focusing on the clearest and most direct expression of the core meaning.
Rules:
1. Return ONLY the translated text without introductory remarks.
2. Eliminate unnecessary filler words while preserving all factual details, numbers, and technical identifiers.
"""
        )
    ]

    public static func matchingPromptPreset(for customPrompt: String) -> PromptPreset? {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return promptPresets.first {
            $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
    }

    public static let defaultTargetLanguage: String = "vi"
    public static let defaultCapacity: Int = 100
    public static let defaultDisplayCapacity: Int = 20
    public static let defaultPollIntervalMs: Int = 200
    public static let defaultMaxThumbnailPixelSize: Int = 220
    // kVK_ANSI_T = 17, optionKey = 2048 (0x0800), shiftKey = 512 (0x0200)
    public static let defaultTranslateHotKeyKeyCode: UInt32 = 17
    public static let defaultTranslateHotKeyModifiers: UInt32 = 2048
    public static let defaultHistoryHotKeyKeyCode: UInt32 = 17
    public static let defaultHistoryHotKeyModifiers: UInt32 = 2560 // optionKey | shiftKey
    public static let defaultLanguage: String = "vi"

    public var validAPIKeys: [String] {
        apiKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public init(
        apiKeys: [String] = [],
        selectedModel: String = AppSettings.defaultModel,
        customSystemPrompt: String = AppSettings.defaultSystemPrompt,
        targetLanguage: String = AppSettings.defaultTargetLanguage,
        enableDoubleCopyTrigger: Bool = true,
        autoTranslateEveryCopy: Bool = false,
        translateHotKeyKeyCode: UInt32 = AppSettings.defaultTranslateHotKeyKeyCode,
        translateHotKeyModifiers: UInt32 = AppSettings.defaultTranslateHotKeyModifiers,
        historyHotKeyKeyCode: UInt32 = AppSettings.defaultHistoryHotKeyKeyCode,
        historyHotKeyModifiers: UInt32 = AppSettings.defaultHistoryHotKeyModifiers,
        autoPasteOnSelection: Bool = true,
        recordHistory: Bool = true,
        capacity: Int = AppSettings.defaultCapacity,
        displayCapacity: Int = AppSettings.defaultDisplayCapacity,
        pollIntervalMs: Int = AppSettings.defaultPollIntervalMs,
        maxThumbnailPixelSize: Int = AppSettings.defaultMaxThumbnailPixelSize,
        launchAtLogin: Bool = false,
        language: String = AppSettings.defaultLanguage,
        ignoredApps: [IgnoredApp] = [],
        automaticallyCheckForUpdates: Bool = true,
        lastUpdateCheckDate: Date? = nil,
        popupWidth: Double? = nil,
        popupHeight: Double? = nil
    ) {
        self.apiKeys = apiKeys
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedModel = trimmedModel.isEmpty ? AppSettings.defaultModel : trimmedModel
        let trimmedPrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customSystemPrompt = trimmedPrompt.isEmpty ? AppSettings.defaultSystemPrompt : customSystemPrompt
        self.targetLanguage = targetLanguage.isEmpty ? AppSettings.defaultTargetLanguage : targetLanguage
        self.enableDoubleCopyTrigger = enableDoubleCopyTrigger
        self.autoTranslateEveryCopy = autoTranslateEveryCopy
        self.translateHotKeyKeyCode = translateHotKeyKeyCode
        self.translateHotKeyModifiers = translateHotKeyModifiers
        self.historyHotKeyKeyCode = historyHotKeyKeyCode
        self.historyHotKeyModifiers = historyHotKeyModifiers
        self.autoPasteOnSelection = autoPasteOnSelection
        self.recordHistory = recordHistory
        self.capacity = max(10, min(capacity, 1000))
        self.displayCapacity = max(5, min(displayCapacity, 500))
        self.pollIntervalMs = max(50, min(pollIntervalMs, 2000))
        self.maxThumbnailPixelSize = max(80, min(maxThumbnailPixelSize, 512))
        self.launchAtLogin = launchAtLogin
        self.language = language
        self.ignoredApps = ignoredApps
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.lastUpdateCheckDate = lastUpdateCheckDate
        self.popupWidth = popupWidth
        self.popupHeight = popupHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.apiKeys = try c.decodeIfPresent([String].self, forKey: .apiKeys) ?? []
        let model = try c.decodeIfPresent(String.self, forKey: .selectedModel) ?? AppSettings.defaultModel
        self.selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppSettings.defaultModel : model
        let prompt = try c.decodeIfPresent(String.self, forKey: .customSystemPrompt) ?? AppSettings.defaultSystemPrompt
        self.customSystemPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppSettings.defaultSystemPrompt : prompt
        self.targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? AppSettings.defaultTargetLanguage
        self.enableDoubleCopyTrigger = try c.decodeIfPresent(Bool.self, forKey: .enableDoubleCopyTrigger) ?? true
        self.autoTranslateEveryCopy = try c.decodeIfPresent(Bool.self, forKey: .autoTranslateEveryCopy) ?? false
        self.translateHotKeyKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .translateHotKeyKeyCode) ?? AppSettings.defaultTranslateHotKeyKeyCode
        self.translateHotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .translateHotKeyModifiers) ?? AppSettings.defaultTranslateHotKeyModifiers
        self.historyHotKeyKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .historyHotKeyKeyCode) ?? AppSettings.defaultHistoryHotKeyKeyCode
        self.historyHotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .historyHotKeyModifiers) ?? AppSettings.defaultHistoryHotKeyModifiers
        self.autoPasteOnSelection = try c.decodeIfPresent(Bool.self, forKey: .autoPasteOnSelection) ?? true
        self.recordHistory = try c.decodeIfPresent(Bool.self, forKey: .recordHistory) ?? true
        let cap = try c.decodeIfPresent(Int.self, forKey: .capacity) ?? AppSettings.defaultCapacity
        self.capacity = max(1, min(cap, 1000))
        let disp = try c.decodeIfPresent(Int.self, forKey: .displayCapacity) ?? AppSettings.defaultDisplayCapacity
        self.displayCapacity = max(5, min(disp, 500))
        let poll = try c.decodeIfPresent(Int.self, forKey: .pollIntervalMs) ?? AppSettings.defaultPollIntervalMs
        self.pollIntervalMs = max(50, min(poll, 2000))
        let thumb = try c.decodeIfPresent(Int.self, forKey: .maxThumbnailPixelSize) ?? AppSettings.defaultMaxThumbnailPixelSize
        self.maxThumbnailPixelSize = max(80, min(thumb, 512))
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.language = try c.decodeIfPresent(String.self, forKey: .language) ?? AppSettings.defaultLanguage
        self.ignoredApps = try c.decodeIfPresent([IgnoredApp].self, forKey: .ignoredApps) ?? []
        self.automaticallyCheckForUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? true
        self.lastUpdateCheckDate = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)
        self.popupWidth = try c.decodeIfPresent(Double.self, forKey: .popupWidth)
        self.popupHeight = try c.decodeIfPresent(Double.self, forKey: .popupHeight)
    }
}
