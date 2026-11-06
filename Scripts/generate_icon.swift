import AppKit
import Foundation

struct IconGenerator {
    let outputURL: URL

    static let iconSpecs: [(name: String, pixelSize: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    func generate() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperTrans_\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for spec in Self.iconSpecs {
            guard let pngData = renderIcon(pixelSize: spec.pixelSize) else {
                throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render \(spec.name)"])
            }
            let fileURL = tempDir.appendingPathComponent(spec.name)
            try pngData.write(to: fileURL)

            if spec.name == "icon_512x512.png" {
                let assetsURL = URL(fileURLWithPath: "Assets/AppIcon.png")
                try? FileManager.default.createDirectory(at: assetsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? pngData.write(to: assetsURL)
            }
        }

        let outputParent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputParent, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", outputURL.path, tempDir.path]
        try process.run()
        process.waitUntilExit()
    }

    /// Pure vector CoreGraphics / NSBezierPath rendering (zero emoji or font text dependencies).
    private func renderIcon(pixelSize: Int) -> Data? {
        let size = NSSize(width: pixelSize, height: pixelSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        let fullRect = NSRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        fullRect.fill()

        let margin = CGFloat(pixelSize) * 0.082
        let iconRect = fullRect.insetBy(dx: margin, dy: margin)
        let cornerRadius = iconRect.width * 0.224

        let baseClipPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        baseClipPath.addClip()

        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.06, green: 0.78, blue: 0.68, alpha: 1.0),
                NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.92, alpha: 1.0),
                NSColor(calibratedRed: 0.35, green: 0.22, blue: 0.85, alpha: 1.0)
            ],
            atLocations: [0.0, 0.5, 1.0],
            colorSpace: .deviceRGB
        )
        gradient?.draw(in: iconRect, angle: -45)

        let cardW = iconRect.width * 0.46
        let cardH = iconRect.height * 0.40
        let cardRadius = cardW * 0.22
        let strokeW = max(1.2, iconRect.width * 0.048)

        // Back card (top-left in screen coordinates -> higher Y in Cocoa coordinates)
        let backCardRect = NSRect(
            x: iconRect.minX + iconRect.width * 0.13,
            y: iconRect.minY + iconRect.height * 0.44,
            width: cardW,
            height: cardH
        )
        let backPath = NSBezierPath(roundedRect: backCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor(calibratedWhite: 1.0, alpha: 0.90).setFill()
        backPath.fill()

        // Pure vector "A" glyph inside back card
        let aPath = NSBezierPath()
        let ax = backCardRect.midX
        let ayBot = backCardRect.minY + backCardRect.height * 0.22
        let ayTop = backCardRect.maxY - backCardRect.height * 0.22
        let aHalfW = backCardRect.width * 0.21
        aPath.move(to: NSPoint(x: ax - aHalfW, y: ayBot))
        aPath.line(to: NSPoint(x: ax, y: ayTop))
        aPath.line(to: NSPoint(x: ax + aHalfW, y: ayBot))
        let barY = ayBot + (ayTop - ayBot) * 0.38
        aPath.move(to: NSPoint(x: ax - aHalfW * 0.62, y: barY))
        aPath.line(to: NSPoint(x: ax + aHalfW * 0.62, y: barY))
        aPath.lineWidth = strokeW
        aPath.lineCapStyle = .round
        aPath.lineJoinStyle = .round
        NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.85, alpha: 1.0).setStroke()
        aPath.stroke()

        // Front card (bottom-right)
        let frontCardRect = NSRect(
            x: iconRect.minX + iconRect.width * 0.41,
            y: iconRect.minY + iconRect.height * 0.16,
            width: cardW,
            height: cardH
        )
        let frontPath = NSBezierPath(roundedRect: frontCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor(calibratedWhite: 1.0, alpha: 0.98).setFill()
        frontPath.fill()

        // Pure vector translation waveform / lines + exchange chevron inside front card
        let linesPath = NSBezierPath()
        let lx1 = frontCardRect.minX + frontCardRect.width * 0.22
        let lx2 = frontCardRect.maxX - frontCardRect.width * 0.22
        let lyTop = frontCardRect.minY + frontCardRect.height * 0.64
        let lyBot = frontCardRect.minY + frontCardRect.height * 0.36
        linesPath.move(to: NSPoint(x: lx1, y: lyTop))
        linesPath.line(to: NSPoint(x: lx2, y: lyTop))
        linesPath.move(to: NSPoint(x: lx1, y: lyBot))
        linesPath.line(to: NSPoint(x: lx1 + (lx2 - lx1) * 0.66, y: lyBot))
        linesPath.lineWidth = strokeW
        linesPath.lineCapStyle = .round
        NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.80, alpha: 1.0).setStroke()
        linesPath.stroke()

        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/Resources/AppIcon.icns"
let generator = IconGenerator(outputURL: URL(fileURLWithPath: outputPath))
try generator.generate()
