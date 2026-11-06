import Foundation

public struct IgnoredApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var iconPath: String?

    public var id: String {
        bundleIdentifier.isEmpty ? name.lowercased() : bundleIdentifier.lowercased()
    }

    public init(bundleIdentifier: String, name: String, iconPath: String? = nil) {
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconPath = iconPath
    }
}
