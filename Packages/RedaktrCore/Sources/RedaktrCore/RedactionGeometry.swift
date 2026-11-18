import CoreGraphics
import Foundation

public enum RedactionGeometry {
    public static func fittedRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    public static func displayRect(
        for normalizedBounds: CGRect,
        imageSize: CGSize,
        fittedRect: CGRect
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }

        let pixelRect = RedactionRenderer.pixelRect(for: normalizedBounds, imageSize: imageSize)
        let scaleX = fittedRect.width / imageSize.width
        let scaleY = fittedRect.height / imageSize.height

        return CGRect(
            x: fittedRect.minX + pixelRect.minX * scaleX,
            y: fittedRect.minY + pixelRect.minY * scaleY,
            width: pixelRect.width * scaleX,
            height: pixelRect.height * scaleY
        )
    }

    public static func normalizedBounds(
        forDisplayRect displayRect: CGRect,
        imageSize: CGSize,
        fittedRect: CGRect
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }

        let scaleX = imageSize.width / fittedRect.width
        let scaleY = imageSize.height / fittedRect.height
        let pixelRect = CGRect(
            x: (displayRect.minX - fittedRect.minX) * scaleX,
            y: (displayRect.minY - fittedRect.minY) * scaleY,
            width: displayRect.width * scaleX,
            height: displayRect.height * scaleY
        )

        return CGRect(
            x: pixelRect.minX / imageSize.width,
            y: 1 - (pixelRect.maxY / imageSize.height),
            width: pixelRect.width / imageSize.width,
            height: pixelRect.height / imageSize.height
        ).standardized
    }
}
