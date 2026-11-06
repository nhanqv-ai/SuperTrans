import Foundation

public struct GlossaryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var sourceTerm: String
    public var targetTerm: String
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceTerm: String,
        targetTerm: String,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceTerm = sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetTerm = targetTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        self.createdAt = createdAt
    }
}

public struct TranslationProject: Identifiable, Codable, Equatable, Sendable {
    public static let defaultProjectId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public let id: UUID
    public var name: String
    public var domainNote: String
    public var glossary: [GlossaryEntry]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        domainNote: String = "",
        glossary: [GlossaryEntry] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? "Mặc định" : trimmedName
        self.domainNote = domainNote.trimmingCharacters(in: .whitespacesAndNewlines)
        self.glossary = glossary
        self.createdAt = createdAt
    }

    public static func makeDefaultProject() -> TranslationProject {
        TranslationProject(
            id: defaultProjectId,
            name: "Mặc định (Chung)",
            domainNote: "",
            glossary: []
        )
    }
}
