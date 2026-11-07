import Foundation
import Combine

public protocol StorageManaging: AnyObject, ObservableObject {
    var items: [TranslationItem] { get }
    var projects: [TranslationProject] { get }
    var activeProject: TranslationProject { get }
    var settings: AppSettings { get set }
    func findCachedTranslation(sourceText: String, targetLanguage: String, projectId: UUID?) -> TranslationItem?
    func touchItem(id: UUID)
    func incrementUsageCount(id: UUID)
    func markTranslationVerified(id: UUID, correctedText: String)
    func addTranslation(item: TranslationItem, imageData: Data?, thumbData: Data?)
    func updateTranslation(id: UUID, translatedText: String, targetLanguage: String, modelUsed: String?)
    func togglePin(id: UUID)
    func toggleMaskItem(id: UUID)
    func deleteItem(id: UUID)
    func clearUnpinnedHistory()
    func getThumbnailURL(for item: TranslationItem) -> URL?
    func getImageURL(for item: TranslationItem) -> URL?
    func getImageData(for item: TranslationItem) -> Data?
    func flushDiskQueue()
    func addIgnoredApp(_ app: IgnoredApp)
    func removeIgnoredApp(bundleIdentifier: String)
    func isAppIgnored(bundleIdentifier: String?, name: String?) -> Bool
}

public final class StorageManager: ObservableObject, StorageManaging, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var _items: [TranslationItem] = []
    private var _projects: [TranslationProject] = [TranslationProject.makeDefaultProject()]
    private var _settings: AppSettings

    public var items: [TranslationItem] {
        lock.lock()
        defer { lock.unlock() }
        return _items
    }

    public var projects: [TranslationProject] {
        lock.lock()
        defer { lock.unlock() }
        return _projects
    }

    public var activeProject: TranslationProject {
        lock.lock()
        defer { lock.unlock() }
        if let found = _projects.first(where: { $0.id == _settings.activeProjectId }) {
            return found
        }
        return _projects.first ?? TranslationProject.makeDefaultProject()
    }

    public var settings: AppSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _settings
        }
        set {
            lock.lock()
            _settings = newValue
            enforceCapacity()
            saveMetadata()
            saveSettings()
            lock.unlock()
            LocalizationManager.shared.setLanguage(code: newValue.language)
            notifyChange()
        }
    }

    public let baseDirectory: URL
    public let imagesDirectory: URL
    public let thumbnailsDirectory: URL
    public let metadataURL: URL
    public let projectsURL: URL
    public let settingsURL: URL

    private let fileQueue = DispatchQueue(label: "com.nhanqv.supertrans.storage.fileio", qos: .utility)
    private let imageCache = NSCache<NSString, NSData>()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = baseDirectory ?? appSupport.appendingPathComponent("SuperTrans", isDirectory: true)
        self.baseDirectory = dir
        self.imagesDirectory = dir.appendingPathComponent("images", isDirectory: true)
        self.thumbnailsDirectory = dir.appendingPathComponent("thumbnails", isDirectory: true)
        self.metadataURL = dir.appendingPathComponent("metadata.json")
        self.projectsURL = dir.appendingPathComponent("projects.json")
        self.settingsURL = dir.appendingPathComponent("settings.json")

        imageCache.countLimit = 50

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        var loadedSettings = AppSettings()
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? dec.decode(AppSettings.self, from: data) {
            loadedSettings = s
            // Migrate legacy default model (gemini-2.5-flash / gemini-2.0-flash) to gemini-3.1-flash-lite
            if loadedSettings.selectedModel == "gemini-2.5-flash" ||
               loadedSettings.selectedModel == "gemini-2.5-flash-lite" ||
               loadedSettings.selectedModel == "gemini-2.0-flash" ||
               loadedSettings.selectedModel == "gemini-2.5-pro" {
                loadedSettings.selectedModel = AppSettings.defaultModel
            }
        }

        self._settings = loadedSettings
        LocalizationManager.shared.setLanguage(code: loadedSettings.language)

        createDirectoriesIfNeeded()
        loadFromDisk()
    }

    private func notifyChange() {
        if Thread.isMainThread {
            self.objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    public func findCachedTranslation(
        sourceText: String,
        targetLanguage: String,
        projectId: UUID? = nil
    ) -> TranslationItem? {
        let normalizedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let targetProjectId = projectId ?? _settings.activeProjectId
        return _items.first { item in
            guard item.contentType == .text,
                  item.projectId == targetProjectId,
                  item.targetLanguage == targetLanguage,
                  let existingSource = item.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return existingSource == normalizedSource && !item.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func touchItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _items.firstIndex(where: { $0.id == id }) else { return }
        var item = _items.remove(at: idx)
        item.createdAt = Date()
        item.usageCount += 1
        _items.insert(item, at: 0)
        saveMetadata()
        notifyChange()
    }

    public func incrementUsageCount(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[idx].usageCount += 1
        saveMetadata()
        notifyChange()
    }

    public func markTranslationVerified(id: UUID, correctedText: String) {
        let trimmed = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _items.firstIndex(where: { $0.id == id }) else { return }
        var item = _items.remove(at: idx)
        item.translatedText = trimmed
        item.isVerified = true
        item.usageCount += 1
        item.createdAt = Date()
        _items.insert(item, at: 0)
        saveMetadata()
        notifyChange()
    }

    public func setTranslationVerified(id: UUID, isVerified: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[idx].isVerified = isVerified
        saveMetadata()
        notifyChange()
    }

    public func buildLearningContext(
        for sourceText: String?,
        targetLanguage: String,
        projectId: UUID? = nil
    ) -> ProjectLearningContext? {
        lock.lock()
        let enabled = _settings.enableAdaptiveLearning
        let targetProjId = projectId ?? _settings.activeProjectId
        let proj = _projects.first(where: { $0.id == targetProjId }) ?? _projects.first ?? TranslationProject.makeDefaultProject()
        let snapshotItems = _items
        lock.unlock()

        guard enabled else { return nil }
        return ProjectMemoryRetriever.retrieveContext(
            project: proj,
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            projectItems: snapshotItems
        )
    }

    // MARK: - Project & Glossary Management

    public func selectActiveProject(id: UUID) {
        lock.lock()
        guard _projects.contains(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        _settings.activeProjectId = id
        saveSettings()
        lock.unlock()
        notifyChange()
    }

    @discardableResult
    public func createProject(name: String, domainNote: String = "") -> TranslationProject {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = TranslationProject(
            name: trimmedName.isEmpty ? "Dự án mới" : trimmedName,
            domainNote: domainNote
        )
        lock.lock()
        _projects.append(project)
        _settings.activeProjectId = project.id
        saveProjects()
        saveSettings()
        lock.unlock()
        notifyChange()
        return project
    }

    public func updateProject(_ project: TranslationProject) {
        lock.lock()
        if let idx = _projects.firstIndex(where: { $0.id == project.id }) {
            _projects[idx] = project
            saveProjects()
        }
        lock.unlock()
        notifyChange()
    }

    public func mergeOrRestoreProjects(_ importedProjects: [TranslationProject]) {
        guard !importedProjects.isEmpty else { return }
        lock.lock()
        for proj in importedProjects {
            if let idx = _projects.firstIndex(where: { $0.id == proj.id }) {
                _projects[idx] = proj
            } else {
                _projects.append(proj)
            }
        }
        if !_projects.contains(where: { $0.id == TranslationProject.defaultProjectId }) {
            _projects.insert(TranslationProject.makeDefaultProject(), at: 0)
        }
        saveProjects()
        lock.unlock()
        notifyChange()
    }

    public func deleteProject(id: UUID) {
        guard id != TranslationProject.defaultProjectId else { return }
        lock.lock()
        _projects.removeAll { $0.id == id }
        if _projects.isEmpty {
            _projects = [TranslationProject.makeDefaultProject()]
        }
        if _settings.activeProjectId == id {
            _settings.activeProjectId = TranslationProject.defaultProjectId
            saveSettings()
        }
        let removedItems = _items.filter { $0.projectId == id }
        _items.removeAll { $0.projectId == id }
        for item in removedItems {
            deleteImageFiles(for: item)
        }
        saveProjects()
        saveMetadata()
        lock.unlock()
        notifyChange()
    }

    public func addOrUpdateGlossaryEntry(
        projectId: UUID? = nil,
        sourceTerm: String,
        targetTerm: String,
        note: String? = nil
    ) {
        let src = sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = targetTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !dst.isEmpty else { return }

        lock.lock()
        let targetId = projectId ?? _settings.activeProjectId
        guard let pIdx = _projects.firstIndex(where: { $0.id == targetId }) else {
            lock.unlock()
            return
        }
        if let gIdx = _projects[pIdx].glossary.firstIndex(where: {
            $0.sourceTerm.caseInsensitiveCompare(src) == .orderedSame
        }) {
            _projects[pIdx].glossary[gIdx].sourceTerm = src
            _projects[pIdx].glossary[gIdx].targetTerm = dst
            if let note = note {
                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                _projects[pIdx].glossary[gIdx].note = trimmedNote.isEmpty ? nil : trimmedNote
            }
        } else {
            let entry = GlossaryEntry(sourceTerm: src, targetTerm: dst, note: note)
            _projects[pIdx].glossary.insert(entry, at: 0)
        }
        saveProjects()
        lock.unlock()
        notifyChange()
    }

    public func removeGlossaryEntry(projectId: UUID, entryId: UUID) {
        lock.lock()
        if let pIdx = _projects.firstIndex(where: { $0.id == projectId }) {
            _projects[pIdx].glossary.removeAll { $0.id == entryId }
            saveProjects()
        }
        lock.unlock()
        notifyChange()
    }

    public func addTranslation(item: TranslationItem, imageData: Data?, thumbData: Data?) {
        lock.lock()
        defer { lock.unlock() }

        guard _settings.recordHistory else { return }

        let resolvedImageName = item.imageFileName ?? (item.contentType == .image ? "\(item.id.uuidString).png" : nil)
        let resolvedThumbName = item.thumbnailFileName ?? (item.contentType == .image ? "\(item.id.uuidString)_thumb.png" : nil)

        if let imgData = imageData, let imgName = resolvedImageName {
            imageCache.setObject(imgData as NSData, forKey: imgName as NSString)
        }

        // Deduplicate identical source text + target language within the same project
        if item.contentType == .text, let sourceText = item.sourceText, !sourceText.isEmpty {
            if let existingIdx = _items.firstIndex(where: {
                $0.contentType == .text &&
                $0.projectId == item.projectId &&
                $0.sourceText == sourceText &&
                $0.targetLanguage == item.targetLanguage
            }) {
                var existing = _items.remove(at: existingIdx)
                existing.translatedText = item.translatedText
                existing.modelUsed = item.modelUsed
                existing.createdAt = Date()
                _items.insert(existing, at: 0)
                saveMetadata()
                notifyChange()
                return
            }
        }

        if let imgData = imageData, let imgName = resolvedImageName {
            let url = imagesDirectory.appendingPathComponent(imgName)
            fileQueue.async {
                try? imgData.write(to: url, options: .atomic)
            }
        }

        if let thData = thumbData, let thName = resolvedThumbName {
            let url = thumbnailsDirectory.appendingPathComponent(thName)
            fileQueue.async {
                try? thData.write(to: url, options: .atomic)
            }
        }

        var itemToStore = item
        if itemToStore.contentType == .image && (itemToStore.imageFileName == nil || itemToStore.thumbnailFileName == nil) {
            itemToStore.imageFileName = resolvedImageName
            itemToStore.thumbnailFileName = resolvedThumbName
        }

        _items.insert(itemToStore, at: 0)
        enforceCapacity()
        saveMetadata()
        notifyChange()
    }

    public func updateTranslation(id: UUID, translatedText: String, targetLanguage: String, modelUsed: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[idx].translatedText = translatedText
        _items[idx].targetLanguage = targetLanguage
        if let modelUsed = modelUsed {
            _items[idx].modelUsed = modelUsed
        }
        _items[idx].createdAt = Date()
        saveMetadata()
        notifyChange()
    }

    public func togglePin(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[index].isPinned.toggle()
        enforceCapacity()
        saveMetadata()
        notifyChange()
    }

    public func toggleMaskItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[index].isMasked.toggle()
        saveMetadata()
        notifyChange()
    }

    public func deleteItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _items.firstIndex(where: { $0.id == id }) else { return }
        let removed = _items.remove(at: index)
        deleteImageFiles(for: removed)
        saveMetadata()
        notifyChange()
    }

    public func clearUnpinnedHistory() {
        lock.lock()
        defer { lock.unlock() }
        let unpinned = _items.filter { !$0.isPinned }
        _items.removeAll { !$0.isPinned }
        for item in unpinned {
            deleteImageFiles(for: item)
        }
        saveMetadata()
        notifyChange()
    }

    public func getThumbnailURL(for item: TranslationItem) -> URL? {
        guard item.contentType == .image else { return nil }
        let name = item.thumbnailFileName ?? "\(item.id.uuidString)_thumb.png"
        return thumbnailsDirectory.appendingPathComponent(name)
    }

    public func getImageURL(for item: TranslationItem) -> URL? {
        guard item.contentType == .image else { return nil }
        let name = item.imageFileName ?? "\(item.id.uuidString).png"
        return imagesDirectory.appendingPathComponent(name)
    }

    public func getImageData(for item: TranslationItem) -> Data? {
        guard item.contentType == .image else { return nil }
        let name = item.imageFileName ?? "\(item.id.uuidString).png"
        if let cached = imageCache.object(forKey: name as NSString) {
            return cached as Data
        }
        let url = imagesDirectory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: url) {
            imageCache.setObject(data as NSData, forKey: name as NSString)
            return data
        }
        return nil
    }

    public func flushDiskQueue() {
        fileQueue.sync {}
    }

    public func addIgnoredApp(_ app: IgnoredApp) {
        lock.lock()
        var current = _settings
        if !current.ignoredApps.contains(where: { $0.id == app.id }) {
            current.ignoredApps.append(app)
            _settings = current
            saveSettings()
        }
        lock.unlock()
        notifyChange()
    }

    public func removeIgnoredApp(bundleIdentifier: String) {
        lock.lock()
        var current = _settings
        current.ignoredApps.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame ||
            $0.name.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        _settings = current
        saveSettings()
        lock.unlock()
        notifyChange()
    }

    public func isAppIgnored(bundleIdentifier: String?, name: String?) -> Bool {
        lock.lock()
        let apps = _settings.ignoredApps
        lock.unlock()

        let bid = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return apps.contains { ignored in
            if !bid.isEmpty && !ignored.bundleIdentifier.isEmpty &&
               ignored.bundleIdentifier.caseInsensitiveCompare(bid) == .orderedSame {
                return true
            }
            if !appName.isEmpty && !ignored.name.isEmpty &&
               ignored.name.caseInsensitiveCompare(appName) == .orderedSame {
                return true
            }
            return false
        }
    }

    private func enforceCapacity() {
        let cap = max(1, _settings.capacity)
        let unpinnedIndices = _items.enumerated().compactMap { idx, item in
            item.isPinned ? nil : idx
        }
        if unpinnedIndices.count > cap {
            let excessIndices = unpinnedIndices.suffix(unpinnedIndices.count - cap)
            for idx in excessIndices.reversed() {
                let removed = _items.remove(at: idx)
                deleteImageFiles(for: removed)
            }
        }
    }

    private func deleteImageFiles(for item: TranslationItem) {
        guard item.contentType == .image else { return }
        if let imgName = item.imageFileName {
            imageCache.removeObject(forKey: imgName as NSString)
            let url = imagesDirectory.appendingPathComponent(imgName)
            fileQueue.async {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if let thName = item.thumbnailFileName {
            let url = thumbnailsDirectory.appendingPathComponent(thName)
            fileQueue.async {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func loadFromDisk() {
        if let pData = try? Data(contentsOf: projectsURL),
           let loadedProjects = try? decoder.decode([TranslationProject].self, from: pData),
           !loadedProjects.isEmpty {
            var projs = loadedProjects
            if let defIdx = projs.firstIndex(where: { $0.id == TranslationProject.defaultProjectId }) {
                if projs[defIdx].name == "Mặc định (Chung)" {
                    projs[defIdx].name = "Mặc định"
                }
            } else {
                projs.insert(TranslationProject.makeDefaultProject(), at: 0)
            }
            _projects = projs
        } else {
            _projects = [TranslationProject.makeDefaultProject()]
        }

        if !_projects.contains(where: { $0.id == _settings.activeProjectId }) {
            _settings.activeProjectId = TranslationProject.defaultProjectId
        }

        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? decoder.decode([TranslationItem].self, from: data) else {
            return
        }
        _items = loaded
    }

    private func saveProjects() {
        let snapshot = _projects
        let url = projectsURL
        let enc = encoder
        fileQueue.async {
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func saveMetadata() {
        let snapshot = _items
        let url = metadataURL
        let enc = encoder
        fileQueue.async {
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func saveSettings() {
        let snapshot = _settings
        let url = settingsURL
        let enc = encoder
        fileQueue.async {
            if let data = try? enc.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
