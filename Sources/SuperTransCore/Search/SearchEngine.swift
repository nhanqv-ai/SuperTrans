import Foundation

public enum SearchEngine {
    public static func normalize(_ text: String) -> String {
        return text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func matches(item: TranslationItem, query: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }

        let translatedNorm = normalize(item.translatedText)
        if translatedNorm.contains(normalizedQuery) {
            return true
        }

        if let source = item.sourceText {
            let sourceNorm = normalize(source)
            if sourceNorm.contains(normalizedQuery) {
                return true
            }
        }

        let langNorm = normalize(LanguageOption.option(for: item.targetLanguage).displayName)
        if langNorm.contains(normalizedQuery) {
            return true
        }

        if item.contentType == .image {
            if "image anh hinh anh photo screenshot".contains(normalizedQuery) {
                return true
            }
        }

        return false
    }

    public static func partition(
        items: [TranslationItem],
        query: String
    ) -> (pinned: [TranslationItem], recent: [TranslationItem]) {
        let filtered = items.filter { matches(item: $0, query: query) }
        let pinned = filtered.filter { $0.isPinned }
        let recent = filtered.filter { !$0.isPinned }
        return (pinned: pinned, recent: recent)
    }
}
