import Foundation

public enum APIKeyStatus: Equatable, Sendable {
    case ready
    case active
    case rateLimited(until: Date)
    case invalid(String)
}

public final class APIKeyRotator: @unchecked Sendable {
    public static let shared = APIKeyRotator()

    private let lock = NSLock()
    private var currentIndex: Int = 0
    private var cooldownUntilByKey: [String: Date] = [:]
    private var invalidReasonByKey: [String: String] = [:]
    private var lastUsedKey: String?

    public init() {}

    /// Returns candidate keys in rotation order:
    /// 1. Healthy keys starting from `currentIndex` (round-robin)
    /// 2. Cooldown keys whose cooldown has expired
    /// 3. Remaining keys in cooldown (ordered by earliest cooldown expiry) as last resort
    public func orderedCandidateKeys(from rawKeys: [String], now: Date = Date()) -> [String] {
        let keys = rawKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !keys.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        // Purge expired cooldowns
        for (k, until) in cooldownUntilByKey where until <= now {
            cooldownUntilByKey.removeValue(forKey: k)
        }

        let startIdx = currentIndex % keys.count
        var rotated: [String] = []
        rotated.reserveCapacity(keys.count)
        for offset in 0..<keys.count {
            let idx = (startIdx + offset) % keys.count
            let key = keys[idx]
            if !rotated.contains(key) {
                rotated.append(key)
            }
        }

        let healthy = rotated.filter { cooldownUntilByKey[$0] == nil && invalidReasonByKey[$0] == nil }
        let rateLimited = rotated
            .filter { cooldownUntilByKey[$0] != nil && invalidReasonByKey[$0] == nil }
            .sorted { (cooldownUntilByKey[$0] ?? .distantFuture) < (cooldownUntilByKey[$1] ?? .distantFuture) }
        let invalid = rotated.filter { invalidReasonByKey[$0] != nil }

        // Advance rotation cursor for next request
        currentIndex = (startIdx + 1) % keys.count

        return healthy + rateLimited + invalid
    }

    public func markSuccess(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        cooldownUntilByKey.removeValue(forKey: trimmed)
        invalidReasonByKey.removeValue(forKey: trimmed)
        lastUsedKey = trimmed
    }

    public func markRateLimited(key: String, cooldownSeconds: TimeInterval = 60, now: Date = Date()) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        cooldownUntilByKey[trimmed] = now.addingTimeInterval(max(5, cooldownSeconds))
    }

    public func markInvalid(key: String, reason: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        invalidReasonByKey[trimmed] = reason
    }

    public func clearState(for key: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) {
            cooldownUntilByKey.removeValue(forKey: key)
            invalidReasonByKey.removeValue(forKey: key)
        } else {
            cooldownUntilByKey.removeAll()
            invalidReasonByKey.removeAll()
            currentIndex = 0
            lastUsedKey = nil
        }
    }

    public func status(for key: String, now: Date = Date()) -> APIKeyStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }

        if let reason = invalidReasonByKey[trimmed] {
            return .invalid(reason)
        }
        if let until = cooldownUntilByKey[trimmed] {
            if until > now {
                return .rateLimited(until: until)
            } else {
                cooldownUntilByKey.removeValue(forKey: trimmed)
            }
        }
        if lastUsedKey == trimmed {
            return .active
        }
        return .ready
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
}
