import Foundation
import AppKit
import SuperTransCore

@main
struct SuperTransTestRunner {
    static var passed = 0
    static var failed = 0

    static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            print("FAIL [line \(line)]: \(message)")
        }
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
        if actual == expected {
            passed += 1
        } else {
            failed += 1
            print("FAIL [line \(line)]: \(message) — expected \(expected), got \(actual)")
        }
    }

    static func main() {
        print("Running SuperTrans Test Suite...")

        testAPIKeyRotator()
        testPromptBuilder()
        testGeminiJSONParsing()
        testStorageManager()
        testSearchEngine()
        testHotKeyFormatting()
        testCursorPopupPositioning()
        testCircularShortcutNavigator()
        testUpdateManagerVersionAndReleaseParsing()
        testCustomPromptPresetsAndVisibility()
        testLegacySettingsWithoutAutoPasteDecoding()
        testFastLatencyOptimizationsAndFallback()
        testGlossaryCSVExportAndImport()
        testDualPreviewImageSyncAcrossRows()

        print("--------------------------------------------------")
        print("SuperTrans Tests Completed: \(passed) passed, \(failed) failed.")
        if failed > 0 {
            Foundation.exit(1)
        }
    }

    static func testAPIKeyRotator() {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTransKeyStateTest_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let rotator = APIKeyRotator(persistenceURL: tempFile)
        let keys = ["AIzaSyKeyOne111111", "AIzaSyKeyTwo222222", "AIzaSyKeyThree3333"]

        let firstOrder = rotator.orderedCandidateKeys(from: keys)
        assertEqual(firstOrder, ["AIzaSyKeyOne111111", "AIzaSyKeyTwo222222", "AIzaSyKeyThree3333"], "First rotation order")

        let secondOrder = rotator.orderedCandidateKeys(from: keys)
        assertEqual(secondOrder, ["AIzaSyKeyTwo222222", "AIzaSyKeyThree3333", "AIzaSyKeyOne111111"], "Round-robin advances cursor")

        // Mark KeyTwo rate-limited & KeyThree invalid -> orderedCandidateKeys skips both completely when KeyOne is healthy!
        let now = Date()
        rotator.markRateLimited(key: "AIzaSyKeyTwo222222", cooldownSeconds: 45, isDailyQuota: false, now: now)
        rotator.markInvalid(key: "AIzaSyKeyThree3333", reason: "API_KEY_INVALID")

        let healthyOnly = rotator.orderedCandidateKeys(from: keys, now: now)
        assertEqual(healthyOnly, ["AIzaSyKeyOne111111"], "Skips rate-limited and invalid keys completely while healthy keys exist")

        // Verify disk persistence of key states across new APIKeyRotator instance
        let reloadedRotator = APIKeyRotator(persistenceURL: tempFile)
        assertEqual(
            reloadedRotator.orderedCandidateKeys(from: keys, now: now),
            ["AIzaSyKeyOne111111"],
            "Reloaded rotator preserves rate-limited and invalid key exclusions from disk"
        )

        // Verify daily quota exhaustion locks key for >= 6 hours and never falls back to it
        reloadedRotator.markRateLimited(key: "AIzaSyKeyOne111111", cooldownSeconds: 60, isDailyQuota: true, now: now)
        if case .quotaExhausted(let until) = reloadedRotator.status(for: "AIzaSyKeyOne111111", now: now) {
            assertTrue(until.timeIntervalSince(now) >= 6 * 3600 - 1, "Daily quota lock lasts at least 6 hours")
        } else {
            assertTrue(false, "Expected .quotaExhausted status for daily quota limit")
        }

        let masked = APIKeyRotator.maskKey("AIzaSyKeyOne111111")
        assertEqual(masked, "AIzaSy••••••1111", "API key masking")
    }

    static func testPromptBuilder() {
        let sys = PromptBuilder.buildSystemInstruction(customSystemPrompt: "", targetLanguageCode: "vi")
        assertTrue(sys.contains("Vietnamese"), "System instruction includes Vietnamese")
        assertTrue(sys.contains("Tiếng Việt"), "System instruction includes Tiếng Việt")

        let userPrompt = PromptBuilder.buildTextUserPrompt(sourceText: "Good morning", targetLanguageCode: "vi")
        assertTrue(userPrompt.contains("Good morning"), "User prompt contains source text")
    }

    static func testGeminiJSONParsing() {
        let validJSON = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  { "text": "Xin chào thế giới" }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let extracted = GeminiClient.extractCandidateText(from: validJSON)
        assertEqual(extracted, "Xin chào thế giới", "Extract candidate text from Gemini response")

        let errorJSON = """
        {
          "error": {
            "code": 429,
            "message": "Resource has been exhausted (e.g. check quota).",
            "status": "RESOURCE_EXHAUSTED"
          }
        }
        """.data(using: .utf8)!
        let errMessage = GeminiClient.extractErrorMessage(from: errorJSON)
        assertEqual(errMessage, "Resource has been exhausted (e.g. check quota).", "Extract error message from Gemini 429")
    }

    static func testStorageManager() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTransTest_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let storage = StorageManager(baseDirectory: tempDir)
        assertEqual(storage.items.count, 0, "Initial storage is empty")

        let item1 = TranslationItem(
            contentType: .text,
            sourceText: "Hello",
            translatedText: "Xin chào",
            targetLanguage: "vi",
            modelUsed: "gemini-2.5-flash"
        )
        storage.addTranslation(item: item1, imageData: nil, thumbData: nil)
        assertEqual(storage.items.count, 1, "Added 1 translation item")
        assertEqual(storage.items.first?.translatedText, "Xin chào", "Stored translated text matches")

        // Verify History Cache lookup (exact & whitespace-trimmed match + targetLanguage match)
        let cachedHit = storage.findCachedTranslation(sourceText: "  Hello \n", targetLanguage: "vi")
        assertEqual(cachedHit?.translatedText, "Xin chào", "findCachedTranslation returns existing translation for same text & language")
        let cachedMissLang = storage.findCachedTranslation(sourceText: "Hello", targetLanguage: "ja")
        assertTrue(cachedMissLang == nil, "findCachedTranslation returns nil for different target language")

        storage.togglePin(id: item1.id)
        assertTrue(storage.items.first?.isPinned == true, "Toggled pin state to true")

        storage.toggleMaskItem(id: item1.id)
        assertTrue(storage.items.first?.isMasked == true, "Toggled mask state to true")
        assertEqual(storage.items.first?.displayTitle, "••••••••", "Masked display title")

        storage.clearUnpinnedHistory()
        assertEqual(storage.items.count, 1, "Pinned item preserved on clearUnpinnedHistory")

        storage.deleteItem(id: item1.id)
        assertEqual(storage.items.count, 0, "Deleted item")

        // Verify custom popup size persistence in AppSettings
        var customSettings = storage.settings
        customSettings.popupWidth = 560
        customSettings.popupHeight = 480
        storage.settings = customSettings
        storage.flushDiskQueue()

        let reloadedStorage = StorageManager(baseDirectory: tempDir)
        assertEqual(reloadedStorage.settings.popupWidth, 560, "Reloaded settings preserves custom popupWidth")
        assertEqual(reloadedStorage.settings.popupHeight, 480, "Reloaded settings preserves custom popupHeight")

        // Verify Multi-Project Isolation & Adaptive Learning Memory
        let projA = reloadedStorage.createProject(name: "Dự án NHK", domainNote: "Bản tin truyền hình Nhật Bản")
        reloadedStorage.addOrUpdateGlossaryEntry(projectId: projA.id, sourceTerm: "代表", targetTerm: "số tổng đài")
        let nhkItem = TranslationItem(
            contentType: .text,
            sourceText: "NHKの代表電話番号にお問い合わせください。",
            translatedText: "Vui lòng liên hệ theo số tổng đài của NHK.",
            targetLanguage: "vi",
            projectId: projA.id
        )
        reloadedStorage.addTranslation(item: nhkItem, imageData: nil, thumbData: nil)
        reloadedStorage.markTranslationVerified(id: nhkItem.id, correctedText: "Xin vui lòng liên hệ tới số tổng đài của đài NHK.")

        // Cache hit inside Project A
        let hitInProjA = reloadedStorage.findCachedTranslation(
            sourceText: "NHKの代表電話番号にお問い合わせください。",
            targetLanguage: "vi",
            projectId: projA.id
        )
        assertEqual(hitInProjA?.translatedText, "Xin vui lòng liên hệ tới số tổng đài của đài NHK.", "Verified translation returned in Project A")
        assertTrue(hitInProjA?.isVerified == true, "Marked as Verified Gold Example")

        // Create Project B -> Cache lookup for Project A's sentence must return nil in Project B (strict isolation!)
        let projB = reloadedStorage.createProject(name: "Dự án Ngân hàng")
        let missInProjB = reloadedStorage.findCachedTranslation(
            sourceText: "NHKの代表電話番号にお問い合わせください。",
            targetLanguage: "vi",
            projectId: projB.id
        )
        assertTrue(missInProjB == nil, "Project B is strictly isolated from Project A's cache")

        // Verify Adaptive Learning Context retrieval in Project A
        let learningCtx = reloadedStorage.buildLearningContext(
            for: "代表番号までご連絡ください。",
            targetLanguage: "vi",
            projectId: projA.id
        )
        assertEqual(learningCtx?.matchedGlossary.count, 1, "Matched glossary entry in Project A")
        assertEqual(learningCtx?.matchedGlossary.first?.targetTerm, "số tổng đài", "Glossary target term matches")
        assertEqual(learningCtx?.fewShotExamples.count, 1, "Retrieved verified Gold Example from Project A")

        let sysPromptWithMemory = PromptBuilder.buildSystemInstruction(
            customSystemPrompt: "",
            targetLanguageCode: "vi",
            learningContext: learningCtx
        )
        assertTrue(sysPromptWithMemory.contains("Dự án NHK"), "System prompt includes project name")
        assertTrue(sysPromptWithMemory.contains("số tổng đài"), "System prompt includes project glossary term")
        assertTrue(sysPromptWithMemory.contains("[Verified Gold Standard]"), "System prompt includes Verified Gold Standard example")
    }

    static func testSearchEngine() {
        let items = [
            TranslationItem(contentType: .text, sourceText: "Artificial Intelligence", translatedText: "Trí tuệ nhân tạo", targetLanguage: "vi", isPinned: true),
            TranslationItem(contentType: .text, sourceText: "Database connection", translatedText: "Kết nối cơ sở dữ liệu", targetLanguage: "vi", isPinned: false)
        ]

        // Diacritic-insensitive search on Vietnamese translation
        let (pinned1, recent1) = SearchEngine.partition(items: items, query: "tri tue nhan tao")
        assertEqual(pinned1.count, 1, "Diacritic-insensitive match on Vietnamese translation")
        assertEqual(recent1.count, 0, "Non-matching recent filtered out")

        // Search on original English text
        let (pinned2, recent2) = SearchEngine.partition(items: items, query: "database")
        assertEqual(pinned2.count, 0, "Non-matching pinned filtered out")
        assertEqual(recent2.count, 1, "Matched English source text")
    }

    static func testHotKeyFormatting() {
        let formatted = HotKeyManager.formatShortcut(
            keyCode: AppSettings.defaultTranslateHotKeyKeyCode,
            modifiers: AppSettings.defaultTranslateHotKeyModifiers
        )
        assertEqual(formatted, "Option + T", "Default translate shortcut formatting")

        let historyFormatted = HotKeyManager.formatShortcut(
            keyCode: AppSettings.defaultHistoryHotKeyKeyCode,
            modifiers: AppSettings.defaultHistoryHotKeyModifiers
        )
        assertEqual(historyFormatted, "Option + Shift + T", "Default history shortcut formatting")
    }

    static func testCursorPopupPositioning() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(width: 420, height: 200)

        // Normal cursor in center of screen -> popup placed directly ABOVE cursor (y = 400 + 14 = 414)
        let normalFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
            mouseLoc: NSPoint(x: 720, y: 400),
            panelSize: panelSize,
            verticalOffset: 14,
            visibleFrame: visibleFrame
        )
        assertEqual(normalFrame.origin.x, 510, "Centered horizontally on cursor")
        assertEqual(normalFrame.origin.y, 414, "Placed 14pt above cursor")

        // Cursor near top edge of screen (y = 850) -> flips BELOW cursor (850 - 200 - 14 = 636)
        let topEdgeFrame = CursorPopupFrameCalculator.calculatePopupFrameAboveCursor(
            mouseLoc: NSPoint(x: 720, y: 850),
            panelSize: panelSize,
            verticalOffset: 14,
            visibleFrame: visibleFrame
        )
        assertEqual(topEdgeFrame.origin.y, 636, "Flipped below cursor when near top screen edge")
    }

    static func testCircularShortcutNavigator() {
        assertEqual(ShortcutNavigator.moveUp(currentIndex: 0, totalCount: 5), 4, "Up from 0 wraps to last item (4)")
        assertEqual(ShortcutNavigator.moveDown(currentIndex: 4, totalCount: 5), 0, "Down from last item (4) wraps to 0")
    }

    static func testUpdateManagerVersionAndReleaseParsing() {
        let v101 = SemanticVersion("v1.0.1")
        let v102 = SemanticVersion("1.0.2")
        let v110 = SemanticVersion("v1.1.0")
        assertTrue(v101 < v102, "1.0.1 < 1.0.2")
        assertTrue(v102 < v110, "1.0.2 < 1.1.0")
        assertTrue(UpdateManager.isVersion("v1.0.2", greaterThan: "1.0.1"), "isVersion v1.0.2 > 1.0.1")

        let releaseJSON = """
        {
          "tag_name": "v1.0.2",
          "html_url": "https://github.com/nhanqv-ai/SuperTrans/releases/tag/v1.0.2",
          "body": "Added automatic & manual update checker",
          "assets": [
            {
              "name": "SuperTrans-v1.0.2.zip",
              "browser_download_url": "https://github.com/nhanqv-ai/SuperTrans/releases/download/v1.0.2/SuperTrans-v1.0.2.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = try? UpdateManager.parseRelease(from: releaseJSON)
        assertTrue(parsed != nil, "UpdateManager.parseRelease parses GitHub release JSON")
        assertEqual(parsed?.versionString, "1.0.2", "Parsed version string is 1.0.2")
        assertEqual(
            parsed?.zipAssetURL?.absoluteString,
            "https://github.com/nhanqv-ai/SuperTrans/releases/download/v1.0.2/SuperTrans-v1.0.2.zip",
            "Parsed zip asset download URL"
        )
    }

    static func testCustomPromptPresetsAndVisibility() {
        var settings = AppSettings()
        assertEqual(settings.visibleBuiltinPromptPresets.count, 5, "All 5 built-in presets visible by default")
        assertEqual(settings.totalVisiblePromptCount, 5, "Total visible prompts is 5 by default")

        let custom1 = CustomPromptPreset(name: "Dịch Keigo", prompt: "Translate into polite Japanese Keigo.", isHidden: false)
        let custom2 = CustomPromptPreset(name: "Review Code", prompt: "Explain code and translate comments.", isHidden: true)
        settings.customPromptPresets = [custom1, custom2]
        settings.selectedPromptId = custom1.id.uuidString
        settings.customSystemPrompt = custom1.prompt

        assertEqual(settings.resolvedActivePromptId, custom1.id.uuidString, "Active prompt resolves to custom1")
        assertEqual(settings.visibleCustomPromptPresets.count, 1, "Only non-hidden custom prompt is in visibleCustomPromptPresets")
        assertEqual(settings.totalVisiblePromptCount, 6, "5 built-in + 1 visible custom = 6")

        // Hide built-in 'default' and 'it_tech'
        settings.hiddenBuiltinPromptIds = ["default", "it_tech"]
        assertEqual(settings.visibleBuiltinPromptPresets.count, 3, "3 built-in presets remain visible")
        assertTrue(settings.hasAnyHiddenPrompt, "hasAnyHiddenPrompt is true when built-in or custom prompts are hidden")

        // When active custom1 is hidden, selectFirstVisiblePrompt switches to first visible built-in ('business')
        settings.customPromptPresets[0].isHidden = true
        settings.selectFirstVisiblePrompt()
        assertEqual(settings.resolvedActivePromptId, "business", "Automatically falls back to first visible prompt ('business')")
    }

    static func testLegacySettingsWithoutAutoPasteDecoding() {
        let legacyJSON = """
        {
          "targetLanguage": "en",
          "autoPasteOnSelection": true,
          "ignoredApps": [{"bundleIdentifier": "com.apple.Terminal", "name": "Terminal"}],
          "recordHistory": false,
          "capacity": 250
        }
        """.data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        assertTrue(decoded != nil, "Legacy AppSettings JSON containing autoPasteOnSelection and ignoredApps decodes cleanly")
        assertEqual(decoded?.targetLanguage, "en", "Preserves targetLanguage from legacy JSON")
        assertEqual(decoded?.recordHistory, false, "Preserves recordHistory from legacy JSON")
        assertEqual(decoded?.capacity, 250, "Preserves capacity from legacy JSON")
    }

    final class MockGeminiURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    static func testFastLatencyOptimizationsAndFallback() {
        // 1. Default & Fallback model configuration
        assertEqual(AppSettings.defaultModel, "gemini-3-flash-preview", "Default model is gemini-3-flash-preview")
        assertEqual(AppSettings.fallbackModel, "gemini-3.1-flash-lite", "Fallback model is gemini-3.1-flash-lite")
        assertEqual(
            GeminiClient.candidateModels(for: "gemini-3-flash-preview"),
            ["gemini-3-flash-preview", "gemini-3.1-flash-lite"],
            "Candidate models chain includes primary then fallback"
        )
        assertEqual(
            GeminiClient.candidateModels(for: "gemini-3.1-flash-lite"),
            ["gemini-3.1-flash-lite", "gemini-3-flash-preview"],
            "Candidate models chain reverses cleanly when fallback is selected as primary"
        )

        // 2. Thinking configuration across Gemini families
        assertEqual(
            GeminiClient.thinkingConfig(for: "gemini-3-flash-preview")?["thinkingLevel"] as? String,
            "MINIMAL",
            "gemini-3-flash-preview uses MINIMAL thinkingLevel"
        )
        assertEqual(
            GeminiClient.thinkingConfig(for: "gemini-3.1-flash-lite")?["thinkingLevel"] as? String,
            "MINIMAL",
            "gemini-3.1-flash-lite also receives MINIMAL thinkingLevel"
        )
        assertEqual(
            GeminiClient.thinkingConfig(for: "gemini-3.5-flash-lite")?["thinkingLevel"] as? String,
            "MINIMAL",
            "gemini-3.5-flash-lite uses MINIMAL thinkingLevel instead of unsupported thinkingBudget=0"
        )
        assertEqual(
            GeminiClient.thinkingConfig(for: "gemini-3.8-flash")?["thinkingLevel"] as? String,
            "LOW",
            "gemini-3.8-flash uses LOW thinkingLevel"
        )
        assertEqual(
            GeminiClient.thinkingConfig(for: "gemini-2.5-flash")?["thinkingBudget"] as? Int,
            0,
            "gemini-2.5-flash uses thinkingBudget=0"
        )
        assertTrue(
            GeminiClient.thinkingConfig(for: "gemini-3.1-flash-tts-preview") == nil,
            "TTS models omit thinkingConfig"
        )

        // 3. Smart ProjectMemoryRetriever filtering (no prompt bloat for unrelated history/glossary)
        var project = TranslationProject(name: "Backend API")
        project.glossary = [
            GlossaryEntry(sourceTerm: "idempotency key", targetTerm: "khoá chống trùng lặp"),
            GlossaryEntry(sourceTerm: "deadlock", targetTerm: "khoá chết")
        ]
        let unrelatedUnverified = TranslationItem(
            contentType: .text,
            sourceText: "Good morning team, have a great weekend!",
            translatedText: "Chào buổi sáng cả nhóm, chúc cuối tuần vui vẻ!",
            targetLanguage: "vi",
            projectId: project.id,
            isVerified: false
        )
        let relatedUnverified = TranslationItem(
            contentType: .text,
            sourceText: "Provide an idempotency key header when retrying POST requests.",
            translatedText: "Cung cấp header khoá chống trùng lặp khi thử lại các yêu cầu POST.",
            targetLanguage: "vi",
            projectId: project.id,
            isVerified: false
        )

        let ctxUnrelated = ProjectMemoryRetriever.retrieveContext(
            project: project,
            sourceText: "SELECT count(*) FROM orders WHERE status = 'pending';",
            targetLanguage: "vi",
            projectItems: [unrelatedUnverified, relatedUnverified]
        )
        assertEqual(ctxUnrelated.matchedGlossary.count, 0, "Unmatched glossary terms excluded for text translation")
        assertEqual(ctxUnrelated.fewShotExamples.count, 0, "Unrelated unverified examples excluded to save prompt tokens")

        let ctxRelated = ProjectMemoryRetriever.retrieveContext(
            project: project,
            sourceText: "Missing idempotency key when retrying POST request",
            targetLanguage: "vi",
            projectItems: [unrelatedUnverified, relatedUnverified]
        )
        assertEqual(ctxRelated.matchedGlossary.count, 1, "Matching glossary term included")
        assertEqual(ctxRelated.fewShotExamples.count, 1, "Similar prior translation included")

        // 4. One-time settings migration from gemini-3.1-flash-lite -> gemini-3-flash-preview
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTransMigrationTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let oldSettingsJSON = """
        {
          "apiKeys": ["AIzaSyTestKey123456"],
          "selectedModel": "gemini-3.1-flash-lite",
          "targetLanguage": "vi"
        }
        """.data(using: .utf8)!
        try? oldSettingsJSON.write(to: tempDir.appendingPathComponent("settings.json"))

        let migratedStorage = StorageManager(baseDirectory: tempDir)
        assertEqual(migratedStorage.settings.selectedModel, "gemini-3-flash-preview", "Migrates legacy gemini-3.1-flash-lite once to gemini-3-flash-preview")
        assertTrue(migratedStorage.settings.hasMigratedToFastFlashV2, "Marks hasMigratedToFastFlashV2 = true")

        // User manually chooses gemini-3.1-flash-lite afterwards -> preserved across reload!
        var manualChoice = migratedStorage.settings
        manualChoice.selectedModel = "gemini-3.1-flash-lite"
        migratedStorage.settings = manualChoice
        migratedStorage.flushDiskQueue()

        let reloadedAfterManual = StorageManager(baseDirectory: tempDir)
        assertEqual(reloadedAfterManual.settings.selectedModel, "gemini-3.1-flash-lite", "Respects manual model choice after one-time migration")

        // 5. HTTP 503 High Demand auto-fallback without penalizing API key
        let tempRotatorURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTrans503Test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempRotatorURL) }
        let rotator = APIKeyRotator(persistenceURL: tempRotatorURL)

        let sessionCfg = URLSessionConfiguration.ephemeral
        sessionCfg.protocolClasses = [MockGeminiURLProtocol.self]
        let mockSession = URLSession(configuration: sessionCfg)
        let client = GeminiClient(session: mockSession, keyRotator: rotator, textTimeout: 8.0, imageTimeout: 15.0)

        var attemptedURLs: [String] = []
        MockGeminiURLProtocol.handler = { req in
            let urlStr = req.url?.absoluteString ?? ""
            attemptedURLs.append(urlStr)
            if urlStr.contains("gemini-3-flash-preview") {
                let errData = """
                {"error":{"code":503,"message":"This model is currently experiencing high demand.","status":"UNAVAILABLE"}}
                """.data(using: .utf8)!
                let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: "HTTP/2", headerFields: nil)!
                return (resp, errData)
            } else {
                let okData = """
                {"candidates":[{"content":{"parts":[{"text":"Xin chào từ model dự phòng"}]}}]}
                """.data(using: .utf8)!
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/2", headerFields: nil)!
                return (resp, okData)
            }
        }

        let sema = DispatchSemaphore(value: 0)
        var fallbackResp: GeminiTranslationResponse?
        let testKey = "AIzaSySingleUserKey9999"
        let settings = AppSettings(apiKeys: [testKey], selectedModel: "gemini-3-flash-preview")

        Task {
            fallbackResp = try? await client.translateText("Hello", targetLanguage: "vi", settings: settings)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 5)

        assertEqual(attemptedURLs.count, 2, "Attempted primary model then immediately fell back to backup model on 503")
        assertEqual(fallbackResp?.translatedText, "Xin chào từ model dự phòng", "Returned translation from fallback model")
        assertEqual(fallbackResp?.modelUsed, "gemini-3.1-flash-lite", "Recorded fallback modelUsed accurately")
        assertEqual(rotator.status(for: testKey), .active, "API key remains .active and is NOT rate-limited on HTTP 503")
    }

    static func testGlossaryCSVExportAndImport() {
        // 1. Empty glossary exports UTF-8 BOM + header row only (acts as CSV template)
        let emptyCSV = GlossaryCSVCodec.encode([], includeBOM: true)
        assertEqual(emptyCSV, "\u{FEFF}source_term,target_term\n", "Empty glossary exports UTF-8 BOM + header line only")
        let decodedEmpty = GlossaryCSVCodec.decode(emptyCSV)
        assertEqual(decodedEmpty.count, 0, "Decoding header-only CSV template returns 0 entries without importing header")

        // 2. Populated glossary with commas, quotes, Vietnamese & Japanese terms round-trips cleanly
        let entries = [
            GlossaryEntry(sourceTerm: "代表", targetTerm: "số tổng đài"),
            GlossaryEntry(sourceTerm: "idempotency, key", targetTerm: "khoá \"chống trùng\""),
            GlossaryEntry(sourceTerm: "pull request", targetTerm: "yêu cầu gộp nhánh")
        ]
        let exportedCSV = GlossaryCSVCodec.encode(entries, includeBOM: true)
        assertTrue(exportedCSV.hasPrefix("\u{FEFF}source_term,target_term\n"), "Populated CSV begins with BOM + header")
        assertTrue(exportedCSV.contains("\"idempotency, key\",\"khoá \"\"chống trùng\"\"\""), "RFC 4180 escapes commas and quotes")

        let decoded = GlossaryCSVCodec.decode(exportedCSV)
        assertEqual(decoded.count, 3, "Decodes all 3 glossary entries while skipping header")
        assertEqual(decoded[0].sourceTerm, "代表", "Preserves CJK source term")
        assertEqual(decoded[0].targetTerm, "số tổng đài", "Preserves Vietnamese target term")
        assertEqual(decoded[1].sourceTerm, "idempotency, key", "Unescapes comma inside quoted CSV field")
        assertEqual(decoded[1].targetTerm, "khoá \"chống trùng\"", "Unescapes doubled quotes inside CSV field")

        // 3. Semicolon CSV (Excel locale save) also imports cleanly
        let semicolonCSV = "source_term;target_term\nwebhook;điểm cuối nhận sự kiện\n"
        let decodedSemi = GlossaryCSVCodec.decode(semicolonCSV)
        assertEqual(decodedSemi.count, 1, "Supports semicolon-delimited CSV from regional Excel locales")
        assertEqual(decodedSemi.first?.sourceTerm, "webhook", "Parses semicolon source term")
        assertEqual(decodedSemi.first?.targetTerm, "điểm cuối nhận sự kiện", "Parses semicolon target term")
    }

    private static func makeSolidPNGData(width: Int, height: Int, color: NSColor) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func testDualPreviewImageSyncAcrossRows() {
        _ = NSApplication.shared
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTransDualPreviewTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url1 = tempDir.appendingPathComponent("img1.png")
        let url2 = tempDir.appendingPathComponent("img2.png")
        try? makeSolidPNGData(width: 100, height: 100, color: .systemBlue).write(to: url1)
        try? makeSolidPNGData(width: 400, height: 50, color: .systemRed).write(to: url2)

        let item1 = TranslationItem(
            contentType: .image,
            translatedText: "Phương án 3: Không đăng ký vào DB",
            targetLanguage: "vi",
            imageFileName: "img1.png",
            thumbnailFileName: "img1.png",
            imageWidth: 100,
            imageHeight: 100
        )
        let item2 = TranslationItem(
            contentType: .image,
            translatedText: "Tính toán điện năng tự cung cấp",
            targetLanguage: "vi",
            imageFileName: "img2.png",
            thumbnailFileName: "img2.png",
            imageWidth: 400,
            imageHeight: 50
        )

        let panel = DualPreviewPanel()
        defer { panel.hide(immediate: true) }

        panel.show(for: item1, imageURL: url1, fallbackThumbnailURL: url1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assertEqual(panel.currentItemId, item1.id, "Preview panel tracks item1 ID")
        assertEqual(panel.displayedImage?.size, NSSize(width: 100, height: 100), "Preview panel loads item1 100x100 image")

        // Simulate hovering directly from Row 1 to Row 2 (item1 onHover(false) races with item2 onHover(true))
        panel.show(for: item2, imageURL: url2, fallbackThumbnailURL: url2)
        panel.hide(forItemId: item1.id, immediate: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        assertEqual(panel.currentItemId, item2.id, "Stale onHover(false) from item1 must NOT clear item2 preview")
        assertTrue(panel.isVisible, "Preview panel stays visible for item2 after stale item1 hover exit")
        assertEqual(panel.displayedImage?.size, NSSize(width: 400, height: 50), "Preview panel updates image immediately to item2 400x50 image without sticking on item1")
    }
}
