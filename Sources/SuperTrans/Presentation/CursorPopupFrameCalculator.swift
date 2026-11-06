import AppKit
import Foundation

public enum CursorPopupFrameCalculator {
    /// Calculates the frame for the translation popup placed directly ABOVE the mouse cursor (`mouseLoc.y + verticalOffset`).
    /// If placing it above exceeds the top edge of `visibleFrame`, it automatically flips below the cursor (`mouseLoc.y - height - verticalOffset`)
    /// and clamps strictly within `visibleFrame`.
    public static func calculatePopupFrameAboveCursor(
        mouseLoc: NSPoint,
        panelSize: NSSize,
        verticalOffset: CGFloat = 14,
        targetScreen: NSScreen? = nil
    ) -> NSRect {
        let screen = targetScreen ?? findScreen(for: mouseLoc)
        guard let screen = screen else {
            return NSRect(
                x: mouseLoc.x - (panelSize.width / 2.0),
                y: mouseLoc.y + verticalOffset,
                width: panelSize.width,
                height: panelSize.height
            )
        }
        return calculatePopupFrameAboveCursor(
            mouseLoc: mouseLoc,
            panelSize: panelSize,
            verticalOffset: verticalOffset,
            visibleFrame: screen.visibleFrame
        )
    }

    public static func calculatePopupFrameAboveCursor(
        mouseLoc: NSPoint,
        panelSize: NSSize,
        verticalOffset: CGFloat = 14,
        visibleFrame: NSRect
    ) -> NSRect {
        var originX = mouseLoc.x - (panelSize.width / 2.0)
        // Default: right above cursor
        var originY = mouseLoc.y + verticalOffset

        // If placing above overflows the top of the screen, place right below cursor
        if originY + panelSize.height > visibleFrame.maxY - 6 {
            let belowY = mouseLoc.y - panelSize.height - verticalOffset
            if belowY >= visibleFrame.minY + 6 {
                originY = belowY
            } else {
                originY = visibleFrame.maxY - panelSize.height - 6
            }
        }

        // Clamp X axis within visibleFrame
        if panelSize.width >= visibleFrame.width {
            originX = visibleFrame.minX
        } else if originX < visibleFrame.minX + 6 {
            originX = visibleFrame.minX + 6
        } else if originX + panelSize.width > visibleFrame.maxX - 6 {
            originX = visibleFrame.maxX - panelSize.width - 6
        }

        // Clamp Y axis within visibleFrame
        if panelSize.height >= visibleFrame.height {
            originY = visibleFrame.minY
        } else if originY < visibleFrame.minY + 6 {
            originY = visibleFrame.minY + 6
        } else if originY + panelSize.height > visibleFrame.maxY - 6 {
            originY = visibleFrame.maxY - panelSize.height - 6
        }

        return NSRect(
            x: round(originX),
            y: round(originY),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Standard centered clamping calculation for the Floating History Panel.
    public static func calculateClampedHistoryPanelFrame(
        mouseLoc: NSPoint,
        panelSize: NSSize,
        targetScreen: NSScreen? = nil
    ) -> NSRect {
        let screen = targetScreen ?? findScreen(for: mouseLoc)
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(
                x: mouseLoc.x - (panelSize.width / 2.0),
                y: mouseLoc.y - (panelSize.height / 2.0),
                width: panelSize.width,
                height: panelSize.height
            )
        }

        var originX = mouseLoc.x - (panelSize.width / 2.0)
        var originY = mouseLoc.y - (panelSize.height / 2.0)

        if originX < visibleFrame.minX { originX = visibleFrame.minX }
        if originX + panelSize.width > visibleFrame.maxX { originX = visibleFrame.maxX - panelSize.width }
        if originY < visibleFrame.minY { originY = visibleFrame.minY }
        if originY + panelSize.height > visibleFrame.maxY { originY = visibleFrame.maxY - panelSize.height }

        return NSRect(x: round(originX), y: round(originY), width: panelSize.width, height: panelSize.height)
    }

    public static func findScreen(
        for point: NSPoint,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        let containing = screens.first { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX &&
            point.y >= screen.frame.minY && point.y <= screen.frame.maxY
        }
        return containing ?? NSScreen.main ?? screens.first
    }
}
