import SwiftUI
import AppKit

/// Custom vector-drawn brand icon for SuperTrans (zero emoji, pure vector geometry).
public struct SuperTransBrandIcon: View {
    public var size: CGFloat = 16

    public init(size: CGFloat = 16) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let corner = w * 0.24

            // Background rounded squircle with gradient
            let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
            let bgPath = Path(roundedRect: bgRect, cornerRadius: corner, style: .continuous)
            let gradient = Gradient(colors: [
                Color(red: 0.08, green: 0.74, blue: 0.68),
                Color(red: 0.14, green: 0.48, blue: 0.94),
                Color(red: 0.36, green: 0.24, blue: 0.86)
            ])
            context.fill(
                bgPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: w, y: h)
                )
            )

            // Back translation card (top-left)
            let cardW = w * 0.50
            let cardH = h * 0.44
            let cardRadius = cardW * 0.22
            let backRect = CGRect(x: w * 0.13, y: h * 0.13, width: cardW, height: cardH)
            let backPath = Path(roundedRect: backRect, cornerRadius: cardRadius, style: .continuous)
            context.fill(backPath, with: .color(Color.white.opacity(0.86)))

            // Vector "A" glyph inside back card
            var aPath = Path()
            let ax = backRect.midX
            let ayTop = backRect.minY + backRect.height * 0.22
            let ayBot = backRect.maxY - backRect.height * 0.20
            let aHalfW = backRect.width * 0.22
            aPath.move(to: CGPoint(x: ax - aHalfW, y: ayBot))
            aPath.addLine(to: CGPoint(x: ax, y: ayTop))
            aPath.addLine(to: CGPoint(x: ax + aHalfW, y: ayBot))
            let barY = ayTop + (ayBot - ayTop) * 0.62
            aPath.move(to: CGPoint(x: ax - aHalfW * 0.62, y: barY))
            aPath.addLine(to: CGPoint(x: ax + aHalfW * 0.62, y: barY))
            context.stroke(
                aPath,
                with: .color(Color(red: 0.10, green: 0.42, blue: 0.85)),
                style: StrokeStyle(lineWidth: max(1.1, w * 0.075), lineCap: .round, lineJoin: .round)
            )

            // Front translation card (bottom-right)
            let frontRect = CGRect(x: w * 0.37, y: h * 0.43, width: cardW, height: cardH)
            let frontPath = Path(roundedRect: frontRect, cornerRadius: cardRadius, style: .continuous)
            context.fill(frontPath, with: .color(Color.white))

            // Vector translation lines / exchange glyph inside front card
            var linesPath = Path()
            let lxStart = frontRect.minX + frontRect.width * 0.22
            let lxEnd = frontRect.maxX - frontRect.width * 0.22
            let ly1 = frontRect.minY + frontRect.height * 0.36
            let ly2 = frontRect.minY + frontRect.height * 0.64
            linesPath.move(to: CGPoint(x: lxStart, y: ly1))
            linesPath.addLine(to: CGPoint(x: lxEnd, y: ly1))
            linesPath.move(to: CGPoint(x: lxStart, y: ly2))
            linesPath.addLine(to: CGPoint(x: lxStart + (lxEnd - lxStart) * 0.68, y: ly2))
            context.stroke(
                linesPath,
                with: .color(Color(red: 0.32, green: 0.22, blue: 0.82)),
                style: StrokeStyle(lineWidth: max(1.1, w * 0.075), lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }

    /// Creates a crisp vector template NSImage for the macOS Menu Bar status item.
    public static func makeMenuBarTemplateImage(pointSize: CGFloat = 16) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: true) { rect in
            let w = rect.width
            let h = rect.height
            let strokeW = max(1.3, w * 0.085)

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Top-left card outline
            let cardW = w * 0.56
            let cardH = h * 0.50
            let r = cardW * 0.22
            let topCard = NSRect(x: w * 0.06, y: h * 0.06, width: cardW, height: cardH)
            let topBezier = NSBezierPath(roundedRect: topCard, xRadius: r, yRadius: r)
            topBezier.lineWidth = strokeW
            topBezier.stroke()

            // Vector "A" inside top-left card
            let aBezier = NSBezierPath()
            let ax = topCard.midX
            let ayTop = topCard.minY + topCard.height * 0.24
            let ayBot = topCard.maxY - topCard.height * 0.22
            let aHalf = topCard.width * 0.21
            aBezier.move(to: NSPoint(x: ax - aHalf, y: ayBot))
            aBezier.line(to: NSPoint(x: ax, y: ayTop))
            aBezier.line(to: NSPoint(x: ax + aHalf, y: ayBot))
            let barY = ayTop + (ayBot - ayTop) * 0.62
            aBezier.move(to: NSPoint(x: ax - aHalf * 0.62, y: barY))
            aBezier.line(to: NSPoint(x: ax + aHalf * 0.62, y: barY))
            aBezier.lineWidth = max(1.1, strokeW * 0.85)
            aBezier.lineCapStyle = .round
            aBezier.lineJoinStyle = .round
            aBezier.stroke()

            // Bottom-right card (filled rounded rect with knockout lines)
            let botCard = NSRect(x: w * 0.38, y: h * 0.44, width: cardW, height: cardH)
            let botBezier = NSBezierPath(roundedRect: botCard, xRadius: r, yRadius: r)
            botBezier.lineWidth = strokeW
            botBezier.stroke()

            let lineBezier = NSBezierPath()
            let lx1 = botCard.minX + botCard.width * 0.24
            let lx2 = botCard.maxX - botCard.width * 0.24
            let ly1 = botCard.minY + botCard.height * 0.38
            let ly2 = botCard.minY + botCard.height * 0.66
            lineBezier.move(to: NSPoint(x: lx1, y: ly1))
            lineBezier.line(to: NSPoint(x: lx2, y: ly1))
            lineBezier.move(to: NSPoint(x: lx1, y: ly2))
            lineBezier.line(to: NSPoint(x: lx1 + (lx2 - lx1) * 0.65, y: ly2))
            lineBezier.lineWidth = max(1.1, strokeW * 0.85)
            lineBezier.lineCapStyle = .round
            lineBezier.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
