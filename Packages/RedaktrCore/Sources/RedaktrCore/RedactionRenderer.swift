import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RedactionRenderer: Sendable {
    public init() {}

    public func renderPNG(
        redacting detections: [Detection],
        in cgImage: CGImage,
        fillColor: CGColor = CGColor(gray: 0, alpha: 1)
    ) throws -> Data {
        let outputImage = try renderImage(redacting: detections, in: cgImage, fillColor: fillColor)

        return try encodePNG(outputImage)
    }

    public func renderJPEG(
        redacting detections: [Detection],
        in cgImage: CGImage,
        fillColor: CGColor = CGColor(gray: 0, alpha: 1),
        compressionQuality: Double = 0.92
    ) throws -> Data {
        let outputImage = try renderImage(redacting: detections, in: cgImage, fillColor: fillColor)

        return try encodeJPEG(outputImage, compressionQuality: compressionQuality)
    }

    public func encodePNG(_ image: CGImage) throws -> Data {
        try encodeImage(image, contentType: .png, properties: Self.strippedImageProperties)
    }

    public func encodeJPEG(_ image: CGImage, compressionQuality: Double = 0.92) throws -> Data {
        let clampedQuality = max(0, min(compressionQuality, 1))
        let properties = [
            kCGImageDestinationLossyCompressionQuality: clampedQuality
        ] as CFDictionary

        return try encodeImage(image, contentType: .jpeg, properties: properties)
    }

    private func encodeImage(_ image: CGImage, contentType: UTType, properties: CFDictionary) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        return data as Data
    }

    private static let strippedImageProperties = NSDictionary() as CFDictionary

    public func renderImage(
        redacting detections: [Detection],
        in cgImage: CGImage,
        fillColor: CGColor = CGColor(gray: 0, alpha: 1)
    ) throws -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: imageRect)
        guard let opaqueFill = fillColor.copy(alpha: 1) else { throw RedaktrCoreError.imageRenderFailed }
        context.setFillColor(opaqueFill)

        for detection in detections {
            context.fill(Self.outwardPixelRect(for: detection.normalizedBounds, imageSize: imageRect.size))
        }

        guard let outputImage = context.makeImage() else {
            throw RedaktrCoreError.imageRenderFailed
        }

        return outputImage
    }

    /// Pixel rect in top-left image coordinates, used by SwiftUI preview layout.
    public static func pixelRect(for normalizedBounds: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBounds.minX * imageSize.width,
            y: (1 - normalizedBounds.maxY) * imageSize.height,
            width: normalizedBounds.width * imageSize.width,
            height: normalizedBounds.height * imageSize.height
        )
    }

    /// Pixel rect in CoreGraphics render coordinates, where Vision-normalized Y remains bottom-origin.
    public static func renderPixelRect(for normalizedBounds: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBounds.minX * imageSize.width,
            y: normalizedBounds.minY * imageSize.height,
            width: normalizedBounds.width * imageSize.width,
            height: normalizedBounds.height * imageSize.height
        )
    }

    public static func outwardPixelRect(for normalizedBounds: CGRect, imageSize: CGSize) -> CGRect {
        let rect = renderPixelRect(for: normalizedBounds, imageSize: imageSize).standardized
        let minX = floor(rect.minX)
        let minY = floor(rect.minY)
        let maxX = ceil(rect.maxX)
        let maxY = ceil(rect.maxY)

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}
