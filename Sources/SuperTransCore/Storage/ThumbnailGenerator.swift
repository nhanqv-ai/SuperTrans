import AppKit
import ImageIO

public enum ThumbnailGenerator {
    public static func generateThumbnail(
        from imageData: Data,
        maxPixelSize: Int = 220
    ) -> (pngData: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let origWidth = cgImage.width
        let origHeight = cgImage.height
        guard origWidth > 0 && origHeight > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(60, maxPixelSize)
        ]

        let thumbCG = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) ?? cgImage
        let rep = NSBitmapImageRep(cgImage: thumbCG)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return (pngData: pngData, width: origWidth, height: origHeight)
    }

    public static func normalizedPNGData(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
