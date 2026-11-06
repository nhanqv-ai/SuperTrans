import Foundation

public enum PromptBuilder {
    public static func buildSystemInstruction(
        customSystemPrompt: String,
        targetLanguageCode: String,
        learningContext: ProjectLearningContext? = nil
    ) -> String {
        let langOption = LanguageOption.option(for: targetLanguageCode)
        let basePrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultSystemPrompt
            : customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = [
            basePrompt,
            """
            Target Language: \(langOption.englishName) (\(langOption.displayName), code: \(langOption.code)).
            Always output the final translation in \(langOption.englishName) (\(langOption.displayName)).
            """
        ]

        if let ctx = learningContext, !ctx.isEmpty {
            var projectBlock: [String] = []
            projectBlock.append("=== PROJECT ADAPTIVE MEMORY (Project: \(ctx.project.name)) ===")

            let domainNote = ctx.project.domainNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !domainNote.isEmpty {
                projectBlock.append("Project Context & Style Guidelines:\n\(domainNote)")
            }

            if !ctx.matchedGlossary.isEmpty {
                let glossaryLines = ctx.matchedGlossary.map { entry -> String in
                    if let note = entry.note, !note.isEmpty {
                        return "- \"\(entry.sourceTerm)\" => \"\(entry.targetTerm)\" (\(note))"
                    } else {
                        return "- \"\(entry.sourceTerm)\" => \"\(entry.targetTerm)\""
                    }
                }.joined(separator: "\n")
                projectBlock.append("Mandatory Project Glossary (Strictly apply these target terms when translating matching source terms):\n\(glossaryLines)")
            }

            if !ctx.fewShotExamples.isEmpty {
                let exampleLines = ctx.fewShotExamples.enumerated().compactMap { idx, item -> String? in
                    guard let src = item.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !src.isEmpty else {
                        return nil
                    }
                    let clippedSrc = String(src.prefix(320))
                    let clippedDst = String(item.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320))
                    let badge = item.isVerified ? "[Verified Gold Standard]" : (item.isPinned ? "[Pinned Preferred]" : "[Prior Project Translation]")
                    return """
                    Example #\(idx + 1) \(badge):
                    Source: \(clippedSrc)
                    Translation: \(clippedDst)
                    """
                }.joined(separator: "\n\n")
                if !exampleLines.isEmpty {
                    projectBlock.append("Reference Translation Memory from this Project (Maintain consistent terminology, tone, and style with these examples):\n\(exampleLines)")
                }
            }

            sections.append(projectBlock.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
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
