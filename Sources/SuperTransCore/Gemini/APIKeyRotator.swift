import Foundation

public enum APIKeyStatus: Equatable, Sendable {
    case ready
    case active
    case rateLimited(until: Date)
    case quotaExhausted(until: Date)
    case invalid(String)
}

public struct PersistedKeyState: Codable, Equatable, Sendable {
    public var cooldownUntil: Date?
    public var isDailyQuotaExhausted: Bool
    public var invalidReason: String?
    public var consecutiveRateLimits: Int

    public init(
        cooldownUntil: Date? = nil,
        isDailyQuotaExhausted: Bool = false,
        invalidReason: String? = nil,
        consecutiveRateLimits: Int = 0
    ) {
        self.cooldownUntil = cooldownUntil
        self.isDailyQuotaExhausted = isDailyQuotaExhausted
        self.invalidReason = invalidReason
        self.consecutiveRateLimits = consecutiveRateLimits
    }
}

public final class APIKeyRotator: @unchecked Sendable {
    public static let shared = APIKeyRotator(persistenceURL: APIKeyRotator.defaultPersistenceURL())

    /// Default lock duration when a key exhausts its daily quota (6 hours).
    public static let dailyQuotaLockDuration: TimeInterval = 6 * 3600

    private let lock = NSLock()
    private var currentIndex: Int = 0
    private var statesByKey: [String: PersistedKeyState] = [:]
    private var lastUsedKey: String?
    private let persistenceURL: URL?

    public static func defaultPersistenceURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SuperTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("key_states.json")
    }

    public init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL
        loadFromDisk()
    }

    /// Returns candidate keys in smart rotation order:
    /// 1. Purges any expired cooldowns/locks (`until <= now`).
    /// 2. Rotates Round-Robin ONLY across healthy keys (`ready` / `active`), completely skipping any key that is `.rateLimited`, `.quotaExhausted`, or `.invalid`.
    /// 3. Only if ZERO healthy keys exist, falls back to short-term `.rateLimited` keys (ordered by earliest expiry), while still NEVER retrying `.invalid` or `.quotaExhausted` keys.
    public func orderedCandidateKeys(from rawKeys: [String], now: Date = Date()) -> [String] {
        var uniqueKeys: [String] = []
        for raw in rawKeys {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !uniqueKeys.contains(trimmed) {
                uniqueKeys.append(trimmed)
            }
        }
        guard !uniqueKeys.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        var didExpireAny = false
        for (key, var state) in statesByKey {
            if let until = state.cooldownUntil, until <= now {
                state.cooldownUntil = nil
                state.isDailyQuotaExhausted = false
                statesByKey[key] = state
                didExpireAny = true
            }
        }
        if didExpireAny {
            saveToDiskLocked()
        }

        // Partition into healthy vs short-term rate-limited (excluding invalid and daily quota exhausted)
        let healthyKeys = uniqueKeys.filter { key in
            guard let state = statesByKey[key] else { return true }
            return state.invalidReason == nil && state.cooldownUntil == nil
        }

        if !healthyKeys.isEmpty {
            let startIdx = currentIndex % healthyKeys.count
            var rotatedHealthy: [String] = []
            rotatedHealthy.reserveCapacity(healthyKeys.count)
            for offset in 0..<healthyKeys.count {
                let idx = (startIdx + offset) % healthyKeys.count
                rotatedHealthy.append(healthyKeys[idx])
            }
            currentIndex = (startIdx + 1) % healthyKeys.count
            return rotatedHealthy
        }

        // Fallback only if ALL keys are currently in cooldown: try short-term RPM rate-limited keys ordered by earliest expiry
        let shortTermRateLimited = uniqueKeys
            .filter { key in
                guard let state = statesByKey[key] else { return false }
                return state.invalidReason == nil && !state.isDailyQuotaExhausted && state.cooldownUntil != nil
            }
            .sorted {
                let d0 = statesByKey[$0]?.cooldownUntil ?? .distantFuture
                let d1 = statesByKey[$1]?.cooldownUntil ?? .distantFuture
                return d0 < d1
            }

        return shortTermRateLimited
    }

    public func markSuccess(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        statesByKey.removeValue(forKey: trimmed)
        lastUsedKey = trimmed
        saveToDiskLocked()
    }

    public func markRateLimited(
        key: String,
        cooldownSeconds: TimeInterval = 60,
        isDailyQuota: Bool = false,
        now: Date = Date()
    ) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }

        var entry = statesByKey[trimmed] ?? PersistedKeyState()
        entry.consecutiveRateLimits += 1
        entry.invalidReason = nil

        // Escalate to daily quota lock if explicitly flagged by Google API OR if the key failed with 429 >= 3 times consecutively
        let treatAsDaily = isDailyQuota || entry.consecutiveRateLimits >= 3
        let effectiveCooldown = treatAsDaily
            ? max(cooldownSeconds, Self.dailyQuotaLockDuration)
            : max(10, cooldownSeconds)

        entry.isDailyQuotaExhausted = treatAsDaily
        entry.cooldownUntil = now.addingTimeInterval(effectiveCooldown)
        statesByKey[trimmed] = entry
        saveToDiskLocked()
    }

    public func markInvalid(key: String, reason: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        var entry = statesByKey[trimmed] ?? PersistedKeyState()
        entry.invalidReason = reason
        entry.cooldownUntil = nil
        entry.isDailyQuotaExhausted = false
        statesByKey[trimmed] = entry
        saveToDiskLocked()
    }

    public func clearState(for key: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) {
            statesByKey.removeValue(forKey: key)
        } else {
            statesByKey.removeAll()
            currentIndex = 0
            lastUsedKey = nil
        }
        saveToDiskLocked()
    }

    public func status(for key: String, now: Date = Date()) -> APIKeyStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }

        if var state = statesByKey[trimmed] {
            if let reason = state.invalidReason {
                return .invalid(reason)
            }
            if let until = state.cooldownUntil {
                if until > now {
                    return state.isDailyQuotaExhausted
                        ? .quotaExhausted(until: until)
                        : .rateLimited(until: until)
                } else {
                    state.cooldownUntil = nil
                    state.isDailyQuotaExhausted = false
                    statesByKey[trimmed] = state
                    saveToDiskLocked()
                }
            }
        }
        if lastUsedKey == trimmed {
            return .active
        }
        return .ready
    }

    public static func formatRemainingTime(until: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(ceil(until.timeIntervalSince(now))))
        if remaining >= 3600 {
            let hours = remaining / 3600
            let mins = (remaining % 3600) / 60
            return "\(hours)h \(mins)m"
        } else if remaining >= 60 {
            let mins = remaining / 60
            let secs = remaining % 60
            return "\(mins)m \(secs)s"
        } else {
            return "\(remaining)s"
        }
    }

    public static func maskKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else {
            return String(repeating: "•", count: max(4, trimmed.count))
        }
        let prefix = trimmed.prefix(6)
        let suffix = trimmed.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }

    private func loadFromDisk() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: PersistedKeyState].self, from: data) {
            statesByKey = decoded
        }
    }

    private func saveToDiskLocked() {
        guard let url = persistenceURL else { return }
        let snapshot = statesByKey
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
