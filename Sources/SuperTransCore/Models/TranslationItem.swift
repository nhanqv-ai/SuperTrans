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
        isMasked: Bool = false
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
