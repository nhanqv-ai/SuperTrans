import Foundation

public struct ProjectLearningContext: Equatable, Sendable {
    public let project: TranslationProject
    public let matchedGlossary: [GlossaryEntry]
    public let fewShotExamples: [TranslationItem]

    public var isEmpty: Bool {
        project.domainNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        matchedGlossary.isEmpty &&
        fewShotExamples.isEmpty
    }

    public init(
        project: TranslationProject,
        matchedGlossary: [GlossaryEntry],
        fewShotExamples: [TranslationItem]
    ) {
        self.project = project
        self.matchedGlossary = matchedGlossary
        self.fewShotExamples = fewShotExamples
    }
}

public enum ProjectMemoryRetriever {
    /// Builds adaptive learning context for the given project, source text (if available), and target language.
    public static func retrieveContext(
        project: TranslationProject,
        sourceText: String?,
        targetLanguage: String,
        projectItems: [TranslationItem],
        maxGlossaryTerms: Int = 20,
        maxFewShotExamples: Int = 4
    ) -> ProjectLearningContext {
        let normalizedQuery = (sourceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Select relevant Glossary entries (prioritize exact substring matches in sourceText, then recent project glossary terms)
        let matchedGlossary: [GlossaryEntry]
        if project.glossary.isEmpty {
            matchedGlossary = []
        } else if normalizedQuery.isEmpty {
            matchedGlossary = Array(project.glossary.prefix(maxGlossaryTerms))
        } else {
            let lowerQuery = normalizedQuery.lowercased()
            var directMatches: [GlossaryEntry] = []
            var otherEntries: [GlossaryEntry] = []
            for entry in project.glossary {
                if !entry.sourceTerm.isEmpty && lowerQuery.contains(entry.sourceTerm.lowercased()) {
                    directMatches.append(entry)
                } else {
                    otherEntries.append(entry)
                }
            }
            matchedGlossary = Array((directMatches + otherEntries).prefix(maxGlossaryTerms))
        }

        // 2. Select top Few-Shot Translation Memory examples from this project
        let candidates = projectItems.filter { item in
            guard item.projectId == project.id,
                  item.contentType == .text,
                  item.targetLanguage == targetLanguage,
                  let src = item.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !src.isEmpty,
                  !item.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return src != normalizedQuery
        }

        guard !candidates.isEmpty else {
            return ProjectLearningContext(
                project: project,
                matchedGlossary: matchedGlossary,
                fewShotExamples: []
            )
        }

        let queryFeatures = extractFeatures(from: normalizedQuery)

        let scored: [(item: TranslationItem, score: Double)] = candidates.enumerated().map { index, item in
            let src = item.sourceText ?? ""
            let candidateFeatures = extractFeatures(from: src)
            let lexicalSim = computeSimilarity(queryFeatures: queryFeatures, candidateFeatures: candidateFeatures)

            // Quality & user-feedback weights (Verified Gold Examples > Pinned > Copied/Reused > Recent)
            var multiplier: Double = 1.0
            var qualityBonus: Double = 0.0

            if item.isVerified {
                multiplier = 3.0
                qualityBonus += 0.35
            } else if item.isPinned {
                multiplier = 2.0
                qualityBonus += 0.20
            }

            if item.usageCount > 0 {
                multiplier *= 1.25
                qualityBonus += min(0.15, Double(item.usageCount) * 0.04)
            }

            // Slight recency bonus for top recent items in the same project to preserve document/session continuity
            let recencyBonus = max(0.0, 0.06 - Double(index) * 0.004)
            let totalScore = (lexicalSim * multiplier) + qualityBonus + recencyBonus
            return (item, totalScore)
        }

        let topExamples = scored
            .sorted { $0.score > $1.score }
            .prefix(maxFewShotExamples)
            .map { $0.item }

        return ProjectLearningContext(
            project: project,
            matchedGlossary: matchedGlossary,
            fewShotExamples: Array(topExamples)
        )
    }

    /// Extracts word tokens and character bigrams so similarity works across English, Vietnamese, and CJK (Japanese/Chinese/Korean).
    public static func extractFeatures(from text: String) -> Set<String> {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return [] }

        var features = Set<String>()

        // Word tokens
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
        for w in words {
            features.insert("w:\(w)")
        }

        // Character bigrams (compact cap to first 300 chars for speed)
        let compact = Array(lower.replacingOccurrences(of: " ", with: "").prefix(300))
        if compact.count >= 2 {
            for i in 0..<(compact.count - 1) {
                features.insert("b:\(compact[i])\(compact[i + 1])")
            }
        }
        return features
    }

    public static func computeSimilarity(queryFeatures: Set<String>, candidateFeatures: Set<String>) -> Double {
        guard !queryFeatures.isEmpty, !candidateFeatures.isEmpty else { return 0.0 }
        let intersection = queryFeatures.intersection(candidateFeatures).count
        guard intersection > 0 else { return 0.0 }
        let denominator = sqrt(Double(queryFeatures.count) * Double(candidateFeatures.count))
        return denominator > 0 ? Double(intersection) / denominator : 0.0
    }
}
