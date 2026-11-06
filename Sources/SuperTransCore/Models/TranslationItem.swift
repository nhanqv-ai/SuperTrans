import Foundation

public struct TranslationItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let contentType: ContentType
    public var sourceText: String?
    public var translatedText: String
    public var targetLanguage: String
    public var modelUsed: String?
    public var imageFileName: String?
    public var thumbnailFileName: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteSize: Int
    public var createdAt: Date
    public var isPinned: Bool
    public var isMasked: Bool
    public var projectId: UUID
    public var isVerified: Bool
    public var usageCount: Int

    public init(
        id: UUID = UUID(),
        contentType: ContentType,
        sourceText: String? = nil,
        translatedText: String,
        targetLanguage: String = "vi",
        modelUsed: String? = nil,
        imageFileName: String? = nil,
        thumbnailFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int = 0,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isMasked: Bool = false,
        projectId: UUID = TranslationProject.defaultProjectId,
        isVerified: Bool = false,
        usageCount: Int = 0
    ) {
        self.id = id
        self.contentType = contentType
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.modelUsed = modelUsed
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = max(0, byteSize)
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isMasked = isMasked
        self.projectId = projectId
        self.isVerified = isVerified
        self.usageCount = max(0, usageCount)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.contentType = try c.decode(ContentType.self, forKey: .contentType)
        self.sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText)
        self.translatedText = try c.decode(String.self, forKey: .translatedText)
        self.targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "vi"
        self.modelUsed = try c.decodeIfPresent(String.self, forKey: .modelUsed)
        self.imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        self.thumbnailFileName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        self.imageWidth = try c.decodeIfPresent(Int.self, forKey: .imageWidth)
        self.imageHeight = try c.decodeIfPresent(Int.self, forKey: .imageHeight)
        self.byteSize = max(0, try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isMasked = try c.decodeIfPresent(Bool.self, forKey: .isMasked) ?? false
        self.projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId) ?? TranslationProject.defaultProjectId
        self.isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        self.usageCount = max(0, try c.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0)
    }

    public var displayTitle: String {
        if isMasked {
            return "••••••••"
        }
        let cleaned = translatedText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned
        }
        if contentType == .image {
            if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
                return "[Image] \(w)x\(h)"
            }
            return "[Image]"
        }
        return sourceText ?? ""
    }
}
