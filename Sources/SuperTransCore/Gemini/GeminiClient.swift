import Foundation

public enum GeminiError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case emptyInput
    case invalidURL
    case rateLimitExhaustedAllKeys(lastMessage: String)
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
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse

    func translateImage(
        imageData: Data,
        mimeType: String,
        targetLanguage: String,
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse

    func testAPIKey(
        _ apiKey: String,
        model: String
    ) async -> Result<String, GeminiError>
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
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeminiError.emptyInput
        }

        let systemInstruction = PromptBuilder.buildSystemInstruction(
            customSystemPrompt: settings.customSystemPrompt,
            targetLanguageCode: targetLanguage
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
        settings: AppSettings
    ) async throws -> GeminiTranslationResponse {
        guard !imageData.isEmpty else {
            throw GeminiError.emptyInput
        }

        let systemInstruction = PromptBuilder.buildSystemInstruction(
            customSystemPrompt: settings.customSystemPrompt,
            targetLanguageCode: targetLanguage
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
        let candidateKeys = keyRotator.orderedCandidateKeys(from: settings.validAPIKeys)
        guard !candidateKeys.isEmpty else {
            throw GeminiError.missingAPIKey
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
                    // If quota or resource exhausted is mentioned in message, rotate to next key
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
                throw GeminiError.httpError(statusCode: 429, message: apiErrorMessage)
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
}
