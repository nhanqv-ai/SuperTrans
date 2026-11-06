import Foundation

public enum GeminiError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case emptyInput
    case invalidURL
    case rateLimitExhaustedAllKeys(lastMessage: String)
    case quotaLimited(message: String, retryAfterSeconds: TimeInterval, isDailyQuota: Bool)
    case invalidAPIKey(message: String)
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return LocalizationManager.shared.tr(.errorMissingAPIKey)
        case .emptyInput:
            return LocalizationManager.shared.tr(.errorEmptyInput)
        case .invalidURL:
            return "Invalid Gemini API endpoint URL."
        case .rateLimitExhaustedAllKeys(let msg):
            return "\(LocalizationManager.shared.tr(.errorAllKeysRateLimited)): \(msg)"
        case .quotaLimited(let msg, _, _):
            return "HTTP 429: \(msg)"
        case .invalidAPIKey(let msg):
            return "\(LocalizationManager.shared.tr(.errorInvalidAPIKey)): \(msg)"
        case .httpError(let code, let msg):
            return "HTTP \(code): \(msg)"
        case .emptyResponse:
            return LocalizationManager.shared.tr(.errorEmptyResponse)
        case .networkError(let msg):
            return msg
        }
    }
}

public struct GeminiTranslationResponse: Equatable, Sendable {
    public let translatedText: String
    public let modelUsed: String
    public let keyUsedMasked: String

    public init(translatedText: String, modelUsed: String, keyUsedMasked: String) {
        self.translatedText = translatedText
        self.modelUsed = modelUsed
        self.keyUsedMasked = keyUsedMasked
    }
}

public protocol GeminiTranslating: AnyObject, Sendable {
    func translateText(
        _ text: String,
        targetLanguage: String,
        settings: AppSettings,
        learningContext: ProjectLearningContext?
    ) async throws -> GeminiTranslationResponse

    func translateImage(
        imageData: Data,
        mimeType: String,
        targetLanguage: String,
        settings: AppSettings,
        learningContext: ProjectLearningContext?
    ) async throws -> GeminiTranslationResponse

    func testAPIKey(
        _ apiKey: String,
        model: String
    ) async -> Result<String, GeminiError>
}

public extension GeminiTranslating {
    func translateText(
        _ text: String,
        targetLanguage: String,
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse {
        try await translateText(text, targetLanguage: targetLanguage, settings: settings, learningContext: nil)
    }

    func translateImage(
        imageData: Data,
        mimeType: String,
        targetLanguage: String,
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse {
        try await translateImage(imageData: imageData, mimeType: mimeType, targetLanguage: targetLanguage, settings: settings, learningContext: nil)
    }
}

public final class GeminiClient: GeminiTranslating, @unchecked Sendable {
    public static let shared = GeminiClient()

    private let session: URLSession
    private let keyRotator: APIKeyRotator

    public init(
        session: URLSession? = nil,
        keyRotator: APIKeyRotator = .shared
    ) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 35
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
        self.keyRotator = keyRotator
    }

    public func translateText(
        _ text: String,
        targetLanguage: String,
        settings: AppSettings,
        learningContext: ProjectLearningContext? = nil
    ) async throws -> GeminiTranslationResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeminiError.emptyInput
        }

        let systemInstruction = PromptBuilder.buildSystemInstruction(
            customSystemPrompt: settings.customSystemPrompt,
            targetLanguageCode: targetLanguage,
            learningContext: learningContext
        )
        let userPrompt = PromptBuilder.buildTextUserPrompt(
            sourceText: trimmed,
            targetLanguageCode: targetLanguage
        )

        let parts: [[String: Any]] = [
            ["text": userPrompt]
        ]

        return try await executeWithKeyRotation(
            parts: parts,
            systemInstruction: systemInstruction,
            settings: settings
        )
    }

    public func translateImage(
        imageData: Data,
        mimeType: String = "image/png",
        targetLanguage: String,
        settings: AppSettings,
        learningContext: ProjectLearningContext? = nil
    ) async throws -> GeminiTranslationResponse {
        guard !imageData.isEmpty else {
            throw GeminiError.emptyInput
        }

        let systemInstruction = PromptBuilder.buildSystemInstruction(
            customSystemPrompt: settings.customSystemPrompt,
            targetLanguageCode: targetLanguage,
            learningContext: learningContext
        )
        let userPrompt = PromptBuilder.buildImageUserPrompt(
            targetLanguageCode: targetLanguage
        )

        let base64Image = imageData.base64EncodedString()
        let parts: [[String: Any]] = [
            ["text": userPrompt],
            [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64Image
                ]
            ]
        ]

        return try await executeWithKeyRotation(
            parts: parts,
            systemInstruction: systemInstruction,
            settings: settings
        )
    }

    public func testAPIKey(
        _ apiKey: String,
        model: String
    ) async -> Result<String, GeminiError> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(.missingAPIKey)
        }
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts: [[String: Any]] = [
            ["text": "Translate 'Hello' to Vietnamese. Reply with one word only."]
        ]

        do {
            let output = try await performSingleRequest(
                apiKey: trimmedKey,
                model: cleanModel,
                parts: parts,
                systemInstruction: nil
            )
            keyRotator.markSuccess(key: trimmedKey)
            return .success(output)
        } catch let err as GeminiError {
            switch err {
            case .quotaLimited(let msg, let retryAfter, let isDaily):
                keyRotator.markRateLimited(key: trimmedKey, cooldownSeconds: retryAfter, isDailyQuota: isDaily)
                return .failure(.httpError(statusCode: 429, message: msg))
            case .rateLimitExhaustedAllKeys(let msg), .httpError(429, let msg):
                keyRotator.markRateLimited(key: trimmedKey)
                return .failure(.httpError(statusCode: 429, message: msg))
            case .invalidAPIKey(let msg):
                keyRotator.markInvalid(key: trimmedKey, reason: msg)
                return .failure(.invalidAPIKey(message: msg))
            default:
                return .failure(err)
            }
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private func executeWithKeyRotation(
        parts: [[String: Any]],
        systemInstruction: String?,
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse {
        let validKeys = settings.validAPIKeys
        guard !validKeys.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let candidateKeys = keyRotator.orderedCandidateKeys(from: validKeys)
        guard !candidateKeys.isEmpty else {
            throw GeminiError.rateLimitExhaustedAllKeys(
                lastMessage: LocalizationManager.shared.languageCode == "vi"
                    ? "Tất cả API Key hiện tại đều đã hết Quota ngày hoặc không hợp lệ."
                    : "All configured API keys have exhausted their daily quota or are invalid."
            )
        }

        let model = settings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultModel
            : settings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)

        var lastRateLimitMessage: String?
        var lastInvalidKeyMessage: String?
        var lastOtherError: GeminiError?

        for apiKey in candidateKeys {
            do {
                let text = try await performSingleRequest(
                    apiKey: apiKey,
                    model: model,
                    parts: parts,
                    systemInstruction: systemInstruction
                )
                keyRotator.markSuccess(key: apiKey)
                return GeminiTranslationResponse(
                    translatedText: text,
                    modelUsed: model,
                    keyUsedMasked: APIKeyRotator.maskKey(apiKey)
                )
            } catch let error as GeminiError {
                switch error {
                case .quotaLimited(let msg, let retryAfter, let isDaily):
                    keyRotator.markRateLimited(key: apiKey, cooldownSeconds: retryAfter, isDailyQuota: isDaily)
                    lastRateLimitMessage = msg
                    continue
                case .httpError(let code, let msg) where code == 429 || code == 503:
                    keyRotator.markRateLimited(key: apiKey, cooldownSeconds: 60)
                    lastRateLimitMessage = msg
                    continue
                case .rateLimitExhaustedAllKeys(let msg):
                    keyRotator.markRateLimited(key: apiKey, cooldownSeconds: 60)
                    lastRateLimitMessage = msg
                    continue
                case .invalidAPIKey(let msg):
                    keyRotator.markInvalid(key: apiKey, reason: msg)
                    lastInvalidKeyMessage = msg
                    continue
                default:
                    lastOtherError = error
                    if let desc = error.errorDescription?.lowercased(),
                       desc.contains("quota") || desc.contains("rate") || desc.contains("exhausted") {
                        keyRotator.markRateLimited(key: apiKey, cooldownSeconds: 60)
                        lastRateLimitMessage = error.errorDescription
                        continue
                    }
                    throw error
                }
            } catch {
                throw GeminiError.networkError(error.localizedDescription)
            }
        }

        if let rateMsg = lastRateLimitMessage {
            throw GeminiError.rateLimitExhaustedAllKeys(lastMessage: rateMsg)
        }
        if let invalidMsg = lastInvalidKeyMessage {
            throw GeminiError.invalidAPIKey(message: invalidMsg)
        }
        throw lastOtherError ?? GeminiError.emptyResponse
    }

    private func performSingleRequest(
        apiKey: String,
        model: String,
        parts: [[String: Any]],
        systemInstruction: String?
    ) async throws -> String {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw GeminiError.invalidURL
        }

        var genConfig: [String: Any] = [
            "temperature": 0.2
        ]
        // Disable thinking overhead on non-lite Gemini models for instant translation response
        let lowerModel = model.lowercased()
        if !lowerModel.contains("lite") && (lowerModel.contains("gemini-3") || lowerModel.contains("gemini-2.5")) {
            genConfig["thinkingConfig"] = [
                "thinkingBudget": 0
            ]
        }

        var requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ],
            "generationConfig": genConfig
        ]

        if let sys = systemInstruction, !sys.isEmpty {
            requestBody["systemInstruction"] = [
                "parts": [
                    ["text": sys]
                ]
            ]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.networkError("Invalid HTTP response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let apiErrorMessage = Self.extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            if httpResponse.statusCode == 429 || apiErrorMessage.lowercased().contains("resource_exhausted") || apiErrorMessage.lowercased().contains("quota") {
                let quotaInfo = Self.extractQuotaLimitMetadata(from: data, httpResponse: httpResponse, fallbackMessage: apiErrorMessage)
                throw GeminiError.quotaLimited(
                    message: apiErrorMessage,
                    retryAfterSeconds: quotaInfo.retryAfterSeconds,
                    isDailyQuota: quotaInfo.isDailyQuota
                )
            }
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                if apiErrorMessage.lowercased().contains("api key") || apiErrorMessage.lowercased().contains("api_key_invalid") || httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw GeminiError.invalidAPIKey(message: apiErrorMessage)
                }
            }
            throw GeminiError.httpError(statusCode: httpResponse.statusCode, message: apiErrorMessage)
        }

        guard let translated = Self.extractCandidateText(from: data),
              !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse
        }

        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractCandidateText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        var combined = ""
        for part in parts {
            if let isThought = part["thought"] as? Bool, isThought {
                continue
            }
            if let text = part["text"] as? String {
                combined += text
            }
        }
        return combined.isEmpty ? nil : combined
    }

    public static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any] else {
            return nil
        }
        if let message = errorObj["message"] as? String, !message.isEmpty {
            return message
        }
        if let status = errorObj["status"] as? String, !status.isEmpty {
            return status
        }
        return nil
    }

    /// Parses Google's HTTP 429 `QuotaFailure` and `RetryInfo` details to distinguish
    /// short-term Per-Minute (RPM/TPM) rate limits from Daily Quota (RPD) exhaustion.
    public static func extractQuotaLimitMetadata(
        from data: Data,
        httpResponse: HTTPURLResponse? = nil,
        fallbackMessage: String = ""
    ) -> (retryAfterSeconds: TimeInterval, isDailyQuota: Bool) {
        var retrySeconds: TimeInterval = 60
        var isDaily = false

        if let headerRetry = httpResponse?.value(forHTTPHeaderField: "Retry-After"),
           let parsedHeader = Double(headerRetry.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsedHeader > 0 {
            retrySeconds = parsedHeader
        }

        let lowerFallback = fallbackMessage.lowercased()
        if lowerFallback.contains("perday") || lowerFallback.contains("per_day") || lowerFallback.contains("per day") || lowerFallback.contains("daily") {
            isDaily = true
        }

        // Parse "retry in 42.5s" from error message if present
        if let range = lowerFallback.range(of: #"retry in ([0-9]+(\.[0-9]+)?)s"#, options: .regularExpression) {
            let matched = String(lowerFallback[range])
                .replacingOccurrences(of: "retry in ", with: "")
                .replacingOccurrences(of: "s", with: "")
            if let val = Double(matched), val > 0 {
                retrySeconds = ceil(val)
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let details = errorObj["details"] as? [[String: Any]] {
            for detail in details {
                if let retryDelayStr = detail["retryDelay"] as? String {
                    let clean = retryDelayStr.trimmingCharacters(in: CharacterSet(charactersIn: "sS \t\n\r"))
                    if let val = Double(clean), val > 0 {
                        retrySeconds = ceil(val)
                    }
                }
                if let violations = detail["violations"] as? [[String: Any]] {
                    for violation in violations {
                        let quotaId = (violation["quotaId"] as? String ?? "").lowercased()
                        let quotaMetric = (violation["quotaMetric"] as? String ?? "").lowercased()
                        let desc = (violation["description"] as? String ?? "").lowercased()
                        let combined = "\(quotaId) \(quotaMetric) \(desc)"
                        if combined.contains("perday") || combined.contains("per_day") || combined.contains("per day") || combined.contains("daily") || combined.contains("rpd") {
                            isDaily = true
                        }
                    }
                }
            }
        }

        if isDaily {
            retrySeconds = max(retrySeconds, APIKeyRotator.dailyQuotaLockDuration)
        }
        return (retryAfterSeconds: retrySeconds, isDailyQuota: isDaily)
    }
}
