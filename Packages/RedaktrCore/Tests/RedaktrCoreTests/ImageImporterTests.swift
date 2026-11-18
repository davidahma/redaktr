import CoreGraphics
import ImageIO
import RedaktrCore
import UniformTypeIdentifiers
import XCTest

final class ImageImporterTests: XCTestCase {
    func testSupportedImageURLsCoverPNGJPEGTIFFAndHEIC() {
        XCTAssertTrue(ImageImporter.supportedContentTypes.contains(.png))
        XCTAssertTrue(ImageImporter.supportedContentTypes.contains(.jpeg))
        XCTAssertTrue(ImageImporter.supportedContentTypes.contains(.tiff))
        XCTAssertTrue(ImageImporter.supportedContentTypes.contains(.heic))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/screenshot.png")))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/photo.jpg")))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/photo.jpeg")))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/scan.tif")))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/scan.tiff")))
        XCTAssertTrue(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/camera.heic")))
        XCTAssertFalse(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/animation.gif")))
        XCTAssertFalse(ImageImporter.isSupportedImageURL(URL(fileURLWithPath: "/tmp/document.pdf")))
    }

    func testRejectsUnsupportedFileTypesBeforeImportingURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try ImageImporter.importImage(from: url)) { error in
            XCTAssertEqual(error as? RedaktrCoreError, .unsupportedImageType)
        }
    }

    func testImportingFileURLDoesNotModifySourceFile() throws {
        let image = try makeTestImage(width: 4, height: 2)
        let data = try encodeImage(image, type: .png)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try Data(contentsOf: url)
        let imported = try ImageImporter.importImage(from: url)
        let after = try Data(contentsOf: url)

        XCTAssertEqual(imported.cgImage.width, 4)
        XCTAssertEqual(imported.cgImage.height, 2)
        XCTAssertEqual(before, after)
    }

    func testMapsExifOrientationValues() {
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 1), .up)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 2), .upMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 3), .down)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 4), .downMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 5), .leftMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 6), .right)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 7), .rightMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 8), .left)
        XCTAssertEqual(CGImagePropertyOrientation(exifRawValue: 99), .up)
    }

    func testImportsExifOrientationForRotatedImageData() throws {
        let image = try makeTestImage(width: 4, height: 2)
        let data = try encodeImage(image, type: .jpeg, exifOrientation: .right)

        let imported = try ImageImporter.importImage(from: data)

        XCTAssertEqual(imported.orientation, .up)
        XCTAssertEqual(imported.cgImage.width, 2)
        XCTAssertEqual(imported.cgImage.height, 4)
    }

    func testRotatedImportExportsRedactionInUprightCoordinateSpace() throws {
        let image = try makeTestImage(width: 4, height: 2)
        let data = try encodeImage(image, type: .jpeg, exifOrientation: .right)
        let imported = try ImageImporter.importImage(from: data)
        let detection = Detection(
            kind: .unknown,
            label: "Manual redaction",
            confidence: 1,
            normalizedBounds: CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25),
            source: .user,
            reason: "Added by the user.",
            boundsPrecision: .manual
        )

        let output = try RedactionRenderer().renderImage(redacting: [detection], in: imported.cgImage)
        let pixels = try rgbaPixels(in: output)

        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 4)
        XCTAssertEqual(pixel(atX: 0, y: 0, width: output.width, pixels: pixels), Pixel(r: 0, g: 0, b: 0, a: 255))
        XCTAssertNotEqual(pixel(atX: 0, y: 3, width: output.width, pixels: pixels), Pixel(r: 0, g: 0, b: 0, a: 255))
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
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

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw RedaktrCoreError.imageRenderFailed
        }
        return image
    }

    private func encodeImage(
        _ image: CGImage,
        type: UTType,
        exifOrientation: CGImagePropertyOrientation = .up
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        let properties = [
            kCGImagePropertyOrientation: exifOrientation.rawValue
        ] as CFDictionary

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        return data as Data
    }

    private func rgbaPixels(in image: CGImage) throws -> [Pixel] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: data.count, by: 4).map { index in
            Pixel(r: data[index], g: data[index + 1], b: data[index + 2], a: data[index + 3])
        }
    }

    private func pixel(atX x: Int, y: Int, width: Int, pixels: [Pixel]) -> Pixel {
        pixels[y * width + x]
    }
}

private struct Pixel: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}
