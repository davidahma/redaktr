import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImportedImage {
    public let cgImage: CGImage
    public let orientation: CGImagePropertyOrientation

    public init(cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

/// A batch retains decoded originals while the user reviews them. 64 megapixels
/// represents about 256 MB of 8-bit RGBA pixels before Vision and preview buffers.
public struct ImageBatchBudget {
    public static let maximumFileCount = 128
    public static let maximumPixels = 64_000_000
    private var remainingPixels = maximumPixels
    private var remainingFiles = maximumFileCount

    public init() {}

    mutating func reserve(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw RedaktrCoreError.invalidImageData }
        guard remainingFiles > 0, width <= remainingPixels / height else { throw ImageBatchLimitExceeded() }
        remainingFiles -= 1
        remainingPixels -= width * height
    }
}

public struct ImageBatchLimitExceeded: Error {
    public init() {}
}

public enum ImageImporter {
    public static let supportedContentTypes: [UTType] = [.png, .jpeg, .tiff, .heic]

    public static func isSupportedImageURL(_ url: URL) -> Bool {
        guard let contentType = contentType(for: url) else { return false }

        return supportedContentTypes.contains { contentType.conforms(to: $0) }
    }

    public static func importImage(from url: URL) throws -> ImportedImage {
        try importImage(from: imageSource(at: url))
    }

    public static func importImage(from url: URL, batchBudget: inout ImageBatchBudget) throws -> ImportedImage {
        let source = try imageSource(at: url)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw RedaktrCoreError.invalidImageData
        }
        var admittedBudget = batchBudget
        try admittedBudget.reserve(width: width, height: height)
        let imported = try importImage(from: source)
        batchBudget = admittedBudget
        return imported
    }

    private static func imageSource(at url: URL) throws -> CGImageSource {
        guard isSupportedImageURL(url) else { throw RedaktrCoreError.unsupportedImageType }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw RedaktrCoreError.invalidImageData }
        return source
    }

    public static func importImage(from data: Data) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw RedaktrCoreError.invalidImageData
        }
        return try importImage(from: source)
    }

    private static func importImage(from source: CGImageSource) throws -> ImportedImage {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RedaktrCoreError.invalidImageData
        }
        let orientation = imageOrientation(from: source)

        return ImportedImage(
            cgImage: try uprightImage(from: cgImage, orientation: orientation),
            orientation: .up
        )
    }

    private static func uprightImage(
        from cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> CGImage {
        guard orientation != .up else { return cgImage }

        let orientedImage = CIImage(cgImage: cgImage).oriented(orientation)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        let extent = orientedImage.extent.integral
        guard let outputImage = context.createCGImage(orientedImage, from: extent) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        return outputImage
    }

    private static func contentType(for url: URL) -> UTType? {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }

        return UTType(filenameExtension: url.pathExtension)
    }

    private static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawValue = properties[kCGImagePropertyOrientation] as? UInt32
        else {
            return .up
        }

        return CGImagePropertyOrientation(exifRawValue: rawValue)
    }
}

public extension CGImagePropertyOrientation {
    init(exifRawValue rawValue: UInt32) {
        switch rawValue {
        case 1: self = .up
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}
