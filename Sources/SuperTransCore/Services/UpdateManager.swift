import Foundation
import AppKit
import Combine
import UserNotifications

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public let prerelease: String?
    public let raw: String

    public init(_ versionString: String) {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed

        var clean = trimmed
        if clean.lowercased().hasPrefix("v") {
            clean = String(clean.dropFirst())
        }

        let buildParts = clean.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true)
        let versionWithoutBuild = buildParts.first.map(String.init) ?? clean

        let parts = versionWithoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let mainPart = parts.first ?? ""
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil

        let numParts = mainPart.split(separator: ".").compactMap { Int($0) }
        self.components = numParts.isEmpty ? [0] : numParts
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left != right { return false }
        }
        return lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left < right { return true }
            if left > right { return false }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(lp), .some(rp)):
            return lp.localizedStandardCompare(rp) == .orderedAscending
        }
    }
}

public struct ReleaseInfo: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let zipAssetURL: URL?

    public var versionString: String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    public init(
        tagName: String,
        name: String,
        releaseNotes: String,
        htmlURL: URL,
        zipAssetURL: URL? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.zipAssetURL = zipAssetURL
    }
}

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(ReleaseInfo)
    case downloading(progress: Double)
    case readyToRestart(ReleaseInfo)
    case error(message: String)
}

public enum UpdateError: LocalizedError, Equatable {
    case invalidReleaseData
    case noAssetFound
    case noReleaseFound
    case rateLimitExceeded
    case httpError(Int)
    case downloadFailed(String)
    case unpackFailed(String)
    case appBundleNotFound
    case binaryNotExecutable
    case signatureVerificationFailed
    case stagingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseData:
            return "Failed to parse release information from GitHub API."
        case .noAssetFound:
            return "No compatible application zip asset found in release."
        case .noReleaseFound:
            return "No releases found on GitHub."
        case .rateLimitExceeded:
            return "GitHub API rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "GitHub API returned HTTP status \(code)."
        case .downloadFailed(let reason):
            return "Failed to download update: \(reason)"
        case .unpackFailed(let reason):
            return "Failed to unpack application zip: \(reason)"
        case .appBundleNotFound:
            return "SuperTrans.app bundle was not found in unpacked archive."
        case .binaryNotExecutable:
            return "SuperTrans executable inside bundle is missing or not executable."
        case .signatureVerificationFailed:
            return "Code signature verification failed."
        case .stagingFailed(let reason):
            return "Failed to stage application into destination: \(reason)"
        }
    }
}

public final class UpdateManager: ObservableObject, @unchecked Sendable {
    public static let shared = UpdateManager()

    @Published public var status: UpdateStatus = .idle
    @Published public var hasPendingUpdate: Bool = false
    @Published public var isBannerDismissedForSession: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var latestRelease: ReleaseInfo? = nil
    @Published public var stagedAppURL: URL? = nil

    private var _customVersion: String? = nil
    public var currentVersion: String {
        get {
            _customVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.5")
        }
        set {
            _customVersion = newValue
        }
    }

    public var apiURL: URL = URL(string: "https://api.github.com/repos/nhanqv-ai/SuperTrans/releases/latest")!
    public var webReleasesLatestURL: URL = URL(string: "https://github.com/nhanqv-ai/SuperTrans/releases/latest")!
    public var enableWebFallbackOnRateLimit: Bool = true
    public var githubToken: String? = {
        let env = ProcessInfo.processInfo.environment
        if let token = env["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if let token = env["GH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if let token = UserDefaults.standard.string(forKey: "GitHubAPIToken")?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        return nil
    }()

    public var stagingTargetURL: URL = {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }
        return URL(fileURLWithPath: "/Applications/SuperTrans.app")
    }()

    public var verifyCodeSignature: Bool = true
    public var appLauncher: (URL) -> Void = { targetURL in
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: targetURL, configuration: config, completionHandler: nil)
    }
    public var terminationHandler: () -> Void = {
        NSApp?.terminate(nil)
    }

    public var urlSession: URLSession
    public weak var storageManager: StorageManager?
    private var periodicTimer: Timer?
    private let lock = NSRecursiveLock()
    private var isCheckTaskInFlight: Bool = false
    private var isCheckUserInitiated: Bool = false
    private var pendingCheckCompletions: [((Result<ReleaseInfo?, Error>) -> Void)] = []
    private var lastETag: String? = nil
    private var lastETagURL: URL? = nil
    private var lastCachedReleaseData: Data? = nil

    public var isBusy: Bool {
        switch status {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    public var shouldShowBanner: Bool {
        guard !isBannerDismissedForSession else { return false }
        switch status {
        case .updateAvailable, .downloading, .readyToRestart:
            return true
        case .error:
            return latestRelease != nil
        default:
            return false
        }
    }

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = session ?? URLSession(configuration: config)
    }

    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return SemanticVersion(v1) > SemanticVersion(v2)
    }

    public static func parseRelease(from data: Data) throws -> ReleaseInfo {
        struct GHAsset: Decodable {
            let name: String?
            let browserDownloadUrl: String?
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        struct GHRelease: Decodable {
            let tagName: String
            let name: String?
            let body: String?
            let htmlUrl: String?
            let assets: [GHAsset]?
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case name
                case body
                case htmlUrl = "html_url"
                case assets
            }
        }

        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        let releaseName = release.name ?? release.tagName
        let notes = release.body ?? ""
        let defaultURL = URL(string: "https://github.com/nhanqv-ai/SuperTrans/releases")!
        let htmlURL: URL
        if let raw = release.htmlUrl, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsed = URL(string: raw) {
            htmlURL = parsed
        } else {
            htmlURL = defaultURL
        }

        var zipURL: URL? = nil
        if let assets = release.assets {
            if let match = assets.first(where: {
                let n = $0.name?.lowercased() ?? ""
                return n.contains("supertrans") && n.hasSuffix(".zip")
            }) ?? assets.first(where: { $0.name?.lowercased().hasSuffix(".zip") == true }) {
                if let raw = match.browserDownloadUrl, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = URL(string: raw) {
                    zipURL = url
                }
            }
        }

        return ReleaseInfo(
            tagName: release.tagName,
            name: releaseName,
            releaseNotes: notes,
            htmlURL: htmlURL,
            zipAssetURL: zipURL
        )
    }

    public static func parseReleaseFromWebRedirectURL(_ redirectURL: URL) -> ReleaseInfo? {
        let path = redirectURL.path
        guard let range = path.range(of: "/releases/tag/") else { return nil }
        let rawTag = String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        let tag = (rawTag.removingPercentEncoding ?? rawTag).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }

        let htmlURL = URL(string: "https://github.com/nhanqv-ai/SuperTrans/releases/tag/\(tag)") ?? redirectURL
        let zipURL = URL(string: "https://github.com/nhanqv-ai/SuperTrans/releases/download/\(tag)/SuperTrans-\(tag).zip")
        return ReleaseInfo(
            tagName: tag,
            name: "SuperTrans \(tag)",
            releaseNotes: "",
            htmlURL: htmlURL,
            zipAssetURL: zipURL
        )
    }

    private func fetchLatestReleaseViaWebRedirect(completion: @escaping (ReleaseInfo?) -> Void) {
        var request = URLRequest(url: webReleasesLatestURL)
        request.httpMethod = "HEAD"
        let sanitizedVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("SuperTrans/\(sanitizedVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0

        let task = urlSession.dataTask(with: request) { _, response, error in
            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                completion(nil)
                return
            }

            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let locationURL = URL(string: location, relativeTo: self.webReleasesLatestURL)?.absoluteURL,
               let release = Self.parseReleaseFromWebRedirectURL(locationURL) {
                completion(release)
                return
            }

            if (200...399).contains(httpResponse.statusCode),
               let finalURL = httpResponse.url,
               let release = Self.parseReleaseFromWebRedirectURL(finalURL) {
                completion(release)
                return
            }

            completion(nil)
        }
        task.resume()
    }

    public func checkForUpdates(userInitiated: Bool = false, completion: ((Result<ReleaseInfo?, Error>) -> Void)? = nil) {
        lock.lock()
        if case .downloading = status {
            let rel = latestRelease
            lock.unlock()
            completion?(.success(rel))
            return
        }

        if isCheckTaskInFlight {
            if userInitiated {
                isCheckUserInitiated = true
            }
            if let completion = completion {
                pendingCheckCompletions.append(completion)
            }
            lock.unlock()
            return
        }

        if !userInitiated, case .readyToRestart(let release) = status {
            lock.unlock()
            completion?(.success(release))
            return
        }

        let previousStatus = self.status
        isCheckTaskInFlight = true
        isCheckUserInitiated = userInitiated
        if let completion = completion {
            pendingCheckCompletions.append(completion)
        }
        let cachedETag = (lastETagURL == apiURL && lastCachedReleaseData != nil) ? lastETag : nil
        lock.unlock()

        if Thread.isMainThread {
            self.status = .checking
        } else {
            DispatchQueue.main.async {
                self.status = .checking
            }
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let sanitizedVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("SuperTrans/\(sanitizedVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = githubToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag = cachedETag, !etag.isEmpty {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        request.timeoutInterval = 15.0

        let finishCallbacks: (Result<ReleaseInfo?, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            self.isCheckTaskInFlight = false
            self.isCheckUserInitiated = false
            let callbacks = self.pendingCheckCompletions
            self.pendingCheckCompletions.removeAll()
            self.lock.unlock()
            for cb in callbacks {
                cb(result)
            }
        }

        let applyRelease: (ReleaseInfo) -> Void = { [weak self] release in
            guard let self = self else { return }
            self.lock.lock()
            let effectiveUserInitiated = self.isCheckUserInitiated
            self.lock.unlock()
            let isNewer = Self.isVersion(release.tagName, greaterThan: self.currentVersion)
            DispatchQueue.main.async {
                let previousLatestTag = self.latestRelease?.tagName
                if isNewer {
                    self.latestRelease = release
                    if case .readyToRestart(let staged) = previousStatus, staged.tagName == release.tagName {
                        self.status = previousStatus
                        self.hasPendingUpdate = true
                        if effectiveUserInitiated {
                            self.isBannerDismissedForSession = false
                        }
                        self.updateLastCheckDate()
                        finishCallbacks(.success(release))
                        return
                    }
                    if let stagedURL = self.stagedAppURL,
                       FileManager.default.fileExists(atPath: stagedURL.path),
                       previousLatestTag == release.tagName {
                        self.status = .readyToRestart(release)
                        self.hasPendingUpdate = true
                        self.isBannerDismissedForSession = false
                        self.updateLastCheckDate()
                        finishCallbacks(.success(release))
                        return
                    }

                    self.status = .updateAvailable(release)
                    self.hasPendingUpdate = true
                    self.isBannerDismissedForSession = false
                    self.postUpdateNotification(release: release)
                    self.updateLastCheckDate()
                    finishCallbacks(.success(release))
                } else {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                        finishCallbacks(.success(nil))
                        return
                    }
                    self.latestRelease = nil
                    self.status = .upToDate(currentVersion: self.currentVersion)
                    self.hasPendingUpdate = false
                    self.updateLastCheckDate()
                    finishCallbacks(.success(nil))
                }
            }
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                    } else {
                        self.status = .error(message: error.localizedDescription)
                    }
                    finishCallbacks(.failure(error))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 304 {
                    self.lock.lock()
                    let cachedData = self.lastCachedReleaseData
                    self.lock.unlock()
                    if let cachedData = cachedData, let release = try? Self.parseRelease(from: cachedData) {
                        applyRelease(release)
                        return
                    }
                } else if httpResponse.statusCode == 404 {
                    let err = UpdateError.noReleaseFound
                    DispatchQueue.main.async {
                        self.status = .error(message: err.localizedDescription)
                        finishCallbacks(.failure(err))
                    }
                    return
                } else if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                    if self.enableWebFallbackOnRateLimit && self.apiURL.host?.lowercased() == "api.github.com" {
                        self.fetchLatestReleaseViaWebRedirect { fallbackRelease in
                            if let fallbackRelease = fallbackRelease {
                                applyRelease(fallbackRelease)
                            } else {
                                let err = UpdateError.rateLimitExceeded
                                DispatchQueue.main.async {
                                    self.updateLastCheckDate()
                                    self.status = .error(message: err.localizedDescription)
                                    finishCallbacks(.failure(err))
                                }
                            }
                        }
                        return
                    }
                } else if !(200...299).contains(httpResponse.statusCode) {
                    let err = UpdateError.httpError(httpResponse.statusCode)
                    DispatchQueue.main.async {
                        self.status = .error(message: err.localizedDescription)
                        finishCallbacks(.failure(err))
                    }
                    return
                }
            }

            guard let data = data else {
                let err = UpdateError.invalidReleaseData
                DispatchQueue.main.async {
                    self.status = .error(message: err.localizedDescription)
                    finishCallbacks(.failure(err))
                }
                return
            }

            do {
                let release = try Self.parseRelease(from: data)
                if let httpResponse = response as? HTTPURLResponse,
                   let etag = httpResponse.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !etag.isEmpty {
                    self.lock.lock()
                    self.lastETag = etag
                    self.lastETagURL = self.apiURL
                    self.lastCachedReleaseData = data
                    self.lock.unlock()
                }
                applyRelease(release)
            } catch {
                DispatchQueue.main.async {
                    self.status = .error(message: error.localizedDescription)
                    finishCallbacks(.failure(error))
                }
            }
        }
        task.resume()
    }

    private func updateLastCheckDate() {
        if let sm = storageManager {
            var s = sm.settings
            s.lastUpdateCheckDate = Date()
            sm.settings = s
        }
    }

    public func dismissBannerForSession() {
        isBannerDismissedForSession = true
    }

    public func checkOnStartupIfNeeded(storageManager: StorageManager) {
        self.storageManager = storageManager
        guard storageManager.settings.automaticallyCheckForUpdates else { return }

        let now = Date()
        if let lastCheck = storageManager.settings.lastUpdateCheckDate {
            let elapsed = now.timeIntervalSince(lastCheck)
            if elapsed >= 0 && elapsed < 86400 {
                return
            }
        }

        checkForUpdates(userInitiated: false)
    }

    public func startPeriodicCheck(interval: TimeInterval = 86400, storageManager: StorageManager? = nil) {
        if let sm = storageManager {
            self.storageManager = sm
        }
        stopPeriodicCheck()

        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.storageManager?.settings.automaticallyCheckForUpdates ?? true {
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    public func stopPeriodicCheck() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    public func postUpdateNotification(release: ReleaseInfo) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let send = {
                let content = UNMutableNotificationContent()
                content.title = "SuperTrans Update Available"
                content.body = "SuperTrans \(release.tagName) is now available."
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "com.nhanqv.supertrans.update.\(release.tagName)",
                    content: content,
                    trigger: nil
                )
                center.add(request, withCompletionHandler: nil)
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { send() }
                }
            default:
                break
            }
        }
    }

    public func startDownloadAndInstall(
        release: ReleaseInfo,
        targetURL: URL? = nil,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        guard let assetURL = release.zipAssetURL else {
            let err = UpdateError.noAssetFound
            self.status = .error(message: err.localizedDescription)
            completion?(.failure(err))
            return
        }

        self.status = .downloading(progress: 0.0)
        self.downloadProgress = 0.0

        downloadAsset(from: assetURL) { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
                self?.status = .downloading(progress: progress)
            }
        } completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    self.status = .error(message: err.localizedDescription)
                    completion?(.failure(err))
                }
            case .success(let zipPath):
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        let downloadDir = zipPath.deletingLastPathComponent()
                        if downloadDir.lastPathComponent.hasPrefix("SuperTrans-Update-") {
                            try? FileManager.default.removeItem(at: downloadDir)
                        } else {
                            try? FileManager.default.removeItem(at: zipPath)
                        }
                    }
                    do {
                        let stagedURL = try self.unpackAndVerify(
                            zipURL: zipPath,
                            destinationURL: targetURL ?? self.stagingTargetURL
                        )
                        DispatchQueue.main.async {
                            self.stagedAppURL = stagedURL
                            self.status = .readyToRestart(release)
                            self.isBannerDismissedForSession = false
                            completion?(.success(stagedURL))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.status = .error(message: error.localizedDescription)
                            completion?(.failure(error))
                        }
                    }
                }
            }
        }
    }

    private func downloadAsset(
        from url: URL,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SuperTrans-Update-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = url.lastPathComponent.isEmpty ? "SuperTrans-update.zip" : url.lastPathComponent
        let dest = tempDir.appendingPathComponent(filename)

        let task = urlSession.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                try? FileManager.default.removeItem(at: tempDir)
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                try? FileManager.default.removeItem(at: tempDir)
                completion(.failure(UpdateError.downloadFailed("HTTP error \(httpResponse.statusCode)")))
                return
            }
            guard let localURL = localURL else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(.failure(UpdateError.downloadFailed("Downloaded file is missing.")))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: localURL, to: dest)
                progressHandler(1.0)
                completion(.success(dest))
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                completion(.failure(error))
            }
        }
        task.resume()
    }

    public func unpackAndVerify(zipURL: URL, destinationURL: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let unpackDir = fm.temporaryDirectory.appendingPathComponent("SuperTrans-Unpacked-\(UUID().uuidString)")
        try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: unpackDir)
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", zipURL.path, unpackDir.path]
        try ditto.run()
        ditto.waitUntilExit()

        var foundAppURL: URL? = nil
        let topItems = try fm.contentsOfDirectory(at: unpackDir, includingPropertiesForKeys: nil)
        if let topApp = topItems.first(where: { $0.pathExtension == "app" }) {
            foundAppURL = topApp
        } else {
            for item in topItems {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let subItems = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                    if let subApp = subItems.first(where: { $0.pathExtension == "app" }) {
                        foundAppURL = subApp
                        break
                    }
                }
            }
        }

        guard let extractedAppURL = foundAppURL else {
            throw UpdateError.appBundleNotFound
        }

        let binaryURL = Bundle(url: extractedAppURL)?.executableURL
            ?? extractedAppURL.appendingPathComponent("Contents/MacOS/SuperTrans")
        guard fm.fileExists(atPath: binaryURL.path) && fm.isExecutableFile(atPath: binaryURL.path) else {
            throw UpdateError.binaryNotExecutable
        }

        if verifyCodeSignature {
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["-v", "--deep", "--strict", extractedAppURL.path]
            try codesign.run()
            codesign.waitUntilExit()
            if codesign.terminationStatus != 0 {
                throw UpdateError.signatureVerificationFailed
            }
        }

        let target = destinationURL ?? stagingTargetURL
        let targetParent = target.deletingLastPathComponent()
        if !fm.fileExists(atPath: targetParent.path) {
            try fm.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: target.path) {
            let backupName = "SuperTrans.app.bak-\(UUID().uuidString)"
            let backupURL = targetParent.appendingPathComponent(backupName)
            do {
                _ = try fm.replaceItemAt(target, withItemAt: extractedAppURL, backupItemName: backupName, options: .usingNewMetadataOnly)
                try? fm.removeItem(at: backupURL)
            } catch {
                try fm.moveItem(at: target, to: backupURL)
                do {
                    try fm.copyItem(at: extractedAppURL, to: target)
                    try? fm.removeItem(at: backupURL)
                } catch {
                    try? fm.moveItem(at: backupURL, to: target)
                    throw UpdateError.stagingFailed(error.localizedDescription)
                }
            }
        } else {
            try fm.copyItem(at: extractedAppURL, to: target)
        }

        return target
    }

    public func restartApp() {
        let target = stagedAppURL ?? stagingTargetURL
        appLauncher(target)
        terminationHandler()
    }
}
