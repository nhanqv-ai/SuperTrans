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
            name: "Mặc định",
            domainNote: "",
            glossary: []
        )
    }
}

public enum GlossaryCSVCodec {
    public static let headerLine = "source_term,target_term"

    private static let recognizedSourceHeaders: Set<String> = [
        "source_term", "sourceterm", "source", "term", "from", "từ gốc", "tu goc", "tu_goc"
    ]
    private static let recognizedTargetHeaders: Set<String> = [
        "target_term", "targetterm", "target", "translation", "to", "nghĩa chuẩn", "nghia chuan", "nghia_chuan"
    ]

    /// Exports glossary entries as UTF-8 CSV (with optional BOM for Excel compatibility).
    /// When `entries` is empty, outputs only the header line so the file doubles as an import template.
    public static func encode(_ entries: [GlossaryEntry], includeBOM: Bool = true) -> String {
        var lines: [String] = [headerLine]
        lines.reserveCapacity(entries.count + 1)
        for entry in entries {
            let src = escapeCSVField(entry.sourceTerm)
            let dst = escapeCSVField(entry.targetTerm)
            lines.append("\(src),\(dst)")
        }
        let prefix = includeBOM ? "\u{FEFF}" : ""
        return prefix + lines.joined(separator: "\n") + "\n"
    }

    /// Parses CSV (RFC 4180 comma or semicolon), TSV, or arrow-delimited glossary text,
    /// stripping UTF-8 BOM and skipping header/comment rows automatically.
    public static func decode(_ raw: String) -> [(sourceTerm: String, targetTerm: String)] {
        var content = raw
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }

        let rows = splitRecordsPreservingQuotes(content)
        var results: [(sourceTerm: String, targetTerm: String)] = []

        for (index, rawRow) in rows.enumerated() {
            let trimmed = rawRow.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let (src, dst) = parseSingleRecord(trimmed) else {
                continue
            }

            if index == 0 || results.isEmpty {
                let lowerSrc = src.lowercased()
                let lowerDst = dst.lowercased()
                if recognizedSourceHeaders.contains(lowerSrc) && recognizedTargetHeaders.contains(lowerDst) {
                    continue
                }
            }

            results.append((sourceTerm: src, targetTerm: dst))
        }

        return results
    }

    public static func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return value
    }

    private static func splitRecordsPreservingQuotes(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if (ch == "\n" || ch == "\r" || ch == "\r\n") && !inQuotes {
                records.append(current)
                current = ""
                if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" {
                    i += 1
                }
            } else {
                current.append(ch)
            }
            i += 1
        }
        if !current.isEmpty {
            records.append(current)
        }
        return records
    }

    private static func parseSingleRecord(_ line: String) -> (String, String)? {
        // 1. Tab-separated (.tsv) if tab exists outside quotes
        if line.contains("\t") && !line.hasPrefix("\"") {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                let src = unquoteAndTrim(parts[0])
                let dst = unquoteAndTrim(parts[1])
                if !src.isEmpty && !dst.isEmpty { return (src, dst) }
            }
        }

        // 2. Standard RFC 4180 comma-separated CSV
        let commaFields = parseDelimitedFields(line, delimiter: ",")
        if commaFields.count >= 2 {
            let src = commaFields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let dst = commaFields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !src.isEmpty && !dst.isEmpty {
                return (src, dst)
            }
        }

        // 3. Semicolon-separated CSV (Excel locale variant)
        let semiFields = parseDelimitedFields(line, delimiter: ";")
        if semiFields.count >= 2 {
            let src = semiFields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let dst = semiFields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !src.isEmpty && !dst.isEmpty {
                return (src, dst)
            }
        }

        // 4. Plain-text arrow separators (`->`, `=>`)
        for sep in ["->", "=>"] {
            if let range = line.range(of: sep) {
                let src = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let dst = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !src.isEmpty && !dst.isEmpty {
                    return (src, dst)
                }
            }
        }

        return nil
    }

    private static func parseDelimitedFields(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    private static func unquoteAndTrim(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2 && s.hasPrefix("\"") && s.hasSuffix("\"") {
            s.removeFirst()
            s.removeLast()
            s = s.replacingOccurrences(of: "\"\"", with: "\"")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
