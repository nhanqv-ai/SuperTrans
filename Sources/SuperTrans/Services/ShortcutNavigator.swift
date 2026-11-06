import AppKit

public enum ShortcutNavigator {
    public static func moveUp(currentIndex: Int?, totalCount: Int) -> Int? {
        guard totalCount > 0 else { return nil }
        guard let current = currentIndex else { return totalCount - 1 }
        if current <= 0 {
            return totalCount - 1
        }
        return current - 1
    }

    public static func moveDown(currentIndex: Int?, totalCount: Int) -> Int? {
        guard totalCount > 0 else { return nil }
        guard let current = currentIndex else { return 0 }
        if current >= totalCount - 1 {
            return 0
        }
        return current + 1
    }

    public static func shortcutIndex(from event: NSEvent) -> Int? {
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let digit = Int(chars), (1...9).contains(digit) else {
            return nil
        }
        return digit - 1
    }
}
