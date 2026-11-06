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
}
