import Foundation

public enum PromptBuilder {
    public static func buildSystemInstruction(
        customSystemPrompt: String,
        targetLanguageCode: String
    ) -> String {
        let langOption = LanguageOption.option(for: targetLanguageCode)
        let basePrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultSystemPrompt
            : customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
\(basePrompt)

Target Language: \(langOption.englishName) (\(langOption.displayName), code: \(langOption.code)).
Always output the final translation in \(langOption.englishName) (\(langOption.displayName)).
"""
    }

    public static func buildTextUserPrompt(
        sourceText: String,
        targetLanguageCode: String
    ) -> String {
        let langOption = LanguageOption.option(for: targetLanguageCode)
        return """
Translate the following text into \(langOption.englishName) (\(langOption.displayName)). Return only the translated result:

\(sourceText)
"""
    }

    public static func buildImageUserPrompt(
        targetLanguageCode: String
    ) -> String {
        let langOption = LanguageOption.option(for: targetLanguageCode)
        return """
Extract all visible text from this image and translate it accurately into \(langOption.englishName) (\(langOption.displayName)).
Preserve paragraph structure and bullet points. Return only the translated content (if the image contains no readable text, briefly describe the image in \(langOption.displayName)).
"""
    }
}
