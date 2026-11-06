import Foundation

public struct LanguageOption: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let code: String
    public let displayName: String
    public let englishName: String

    public var id: String { code }

    public init(code: String, displayName: String, englishName: String) {
        self.code = code
        self.displayName = displayName
        self.englishName = englishName
    }

    public static let supported: [LanguageOption] = [
        LanguageOption(code: "vi", displayName: "Tiếng Việt", englishName: "Vietnamese"),
        LanguageOption(code: "en", displayName: "English (Tiếng Anh)", englishName: "English"),
        LanguageOption(code: "ja", displayName: "日本語 (Tiếng Nhật)", englishName: "Japanese"),
        LanguageOption(code: "ko", displayName: "한국어 (Tiếng Hàn)", englishName: "Korean"),
        LanguageOption(code: "zh-CN", displayName: "简体中文 (Tiếng Trung Giản thể)", englishName: "Simplified Chinese"),
        LanguageOption(code: "zh-TW", displayName: "繁體中文 (Tiếng Trung Phồn thể)", englishName: "Traditional Chinese"),
        LanguageOption(code: "fr", displayName: "Français (Tiếng Pháp)", englishName: "French"),
        LanguageOption(code: "de", displayName: "Deutsch (Tiếng Đức)", englishName: "German"),
        LanguageOption(code: "es", displayName: "Español (Tiếng Tây Ban Nha)", englishName: "Spanish"),
        LanguageOption(code: "ru", displayName: "Русский (Tiếng Nga)", englishName: "Russian"),
        LanguageOption(code: "th", displayName: "ไทย (Tiếng Thái)", englishName: "Thai")
    ]

    public static func option(for code: String) -> LanguageOption {
        return supported.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame })
            ?? LanguageOption(code: code, displayName: code.uppercased(), englishName: code)
    }
}
