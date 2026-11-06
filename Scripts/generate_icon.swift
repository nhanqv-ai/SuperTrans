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

        let backCardRect = NSRect(
            x: iconRect.minX + iconRect.width * 0.14,
            y: iconRect.minY + iconRect.height * 0.42,
            width: cardW,
            height: cardH
        )
        let backPath = NSBezierPath(roundedRect: backCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor(calibratedWhite: 1.0, alpha: 0.88).setFill()
        backPath.fill()

        let frontCardRect = NSRect(
            x: iconRect.minX + iconRect.width * 0.40,
            y: iconRect.minY + iconRect.height * 0.18,
            width: cardW,
            height: cardH
        )
        let frontPath = NSBezierPath(roundedRect: frontCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor(calibratedWhite: 1.0, alpha: 0.98).setFill()
        frontPath.fill()

        let fontSize = cardH * 0.56
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let backAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.85, alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        let aStr = NSString(string: "A")
        let aSize = aStr.size(withAttributes: backAttrs)
        aStr.draw(
            in: NSRect(
                x: backCardRect.minX,
                y: backCardRect.midY - aSize.height / 2,
                width: backCardRect.width,
                height: aSize.height
            ),
            withAttributes: backAttrs
        )

        let frontAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize * 0.88, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.80, alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        let vStr = NSString(string: "VI")
        let vSize = vStr.size(withAttributes: frontAttrs)
        vStr.draw(
            in: NSRect(
                x: frontCardRect.minX,
                y: frontCardRect.midY - vSize.height / 2,
                width: frontCardRect.width,
                height: vSize.height
            ),
            withAttributes: frontAttrs
        )

        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/Resources/AppIcon.icns"
let generator = IconGenerator(outputURL: URL(fileURLWithPath: outputPath))
try generator.generate()
