import CoreGraphics
import Foundation
import ImageIO
import RedaktrCore
import UniformTypeIdentifiers
import XCTest

final class RedactionRendererTests: XCTestCase {
    func testRenderImageReplacesRedactedPixelsWithOpaqueFill() throws {
        let image = try makeSolidImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let detection = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.95,
            normalizedBounds: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )

        let output = try RedactionRenderer().renderImage(redacting: [detection], in: image)
        let pixels = try rgbaPixels(in: output)

        XCTAssertEqual(pixel(atX: 4, y: 4, width: output.width, pixels: pixels), Pixel(r: 0, g: 0, b: 0, a: 255))
        XCTAssertEqual(pixel(atX: 0, y: 0, width: output.width, pixels: pixels), Pixel(r: 255, g: 255, b: 255, a: 255))
    }

    func testRescanWithSmallerManualMaskKeepsEntireDetectedAreaOpaque() throws {
        let original = try makeSolidImage(width: 20, height: 20, color: CGColor(gray: 1, alpha: 1))
        let automatic = Detection(kind: .email, label: "Email", confidence: 1,
            normalizedBounds: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2),
            source: .deterministic, reason: "test", boundsPrecision: .tight)
        let manual = RedactionPlan.manualRedaction(bounds: CGRect(x: 0.35, y: 0.43, width: 0.1, height: 0.1))
        let plan = RedactionPlan(textDetections: [automatic], manualDetections: [manual])
        let data = try RedactionRenderer().renderPNG(redacting: plan.activeDetections, in: original,
            fillColor: CGColor(gray: 0, alpha: 0.15))
        let pixels = try rgbaPixels(in: try decodedImage(from: imageSource(from: data)))
        for x in 2..<18 {
            XCTAssertEqual(pixel(atX: x, y: 10, width: 20, pixels: pixels), Pixel(r: 0, g: 0, b: 0, a: 255))
        }
        XCTAssertEqual(pixel(atX: 0, y: 10, width: 20, pixels: pixels), Pixel(r: 255, g: 255, b: 255, a: 255))
    }

    func testInactiveManualRegionDoesNotDisplaceActiveAutomaticMaskOnRescan() {
        let automatic = Detection(kind: .email, label: "Email", confidence: 1,
            normalizedBounds: CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.1),
            source: .deterministic, reason: "test", boundsPrecision: .tight)
        let manual = RedactionPlan.manualRedaction(bounds: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.5))
        let plan = RedactionPlan(textDetections: [automatic], manualDetections: [manual],
            manualActiveStates: [manual.id: false])
        XCTAssertEqual(plan.activeDetections, [automatic])
    }

    func testRenderImageUsesBottomOriginVisionBoundsWithoutVerticalFlip() throws {
        let image = try makeSolidImage(width: 10, height: 10, color: CGColor(gray: 1, alpha: 1))
        let detection = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.95,
            normalizedBounds: CGRect(x: 0.20, y: 0.70, width: 0.30, height: 0.20),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )

        let output = try RedactionRenderer().renderImage(redacting: [detection], in: image)
        let pixels = try rgbaPixels(in: output)

        XCTAssertEqual(pixel(atX: 3, y: 1, width: output.width, pixels: pixels), Pixel(r: 0, g: 0, b: 0, a: 255))
        XCTAssertEqual(pixel(atX: 3, y: 8, width: output.width, pixels: pixels), Pixel(r: 255, g: 255, b: 255, a: 255))
    }

    func testRenderPNGStripsAdversarialSourceMetadata() throws {
        let image = try makeSolidImage(width: 4, height: 4, color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        let sourceData = try encodeImageWithPrivateMetadata(image)
        let source = try imageSource(from: sourceData)
        let sourceProperties = try properties(from: source)
        XCTAssertNotNil(sourceProperties[kCGImagePropertyExifDictionary])
        XCTAssertNotNil(sourceProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(sourceProperties[kCGImagePropertyTIFFDictionary])

        let sourceImage = try decodedImage(from: source)
        let outputData = try RedactionRenderer().renderPNG(redacting: [], in: sourceImage)
        let outputProperties = try properties(from: try imageSource(from: outputData))
        let outputExif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        XCTAssertNil(outputExif?[kCGImagePropertyExifUserComment])
        XCTAssertNil(outputProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(outputProperties[kCGImagePropertyTIFFDictionary])
        XCTAssertNil(outputProperties[kCGImagePropertyOrientation])
        XCTAssertNil(outputData.range(of: Data("Secret Camera".utf8)))
        XCTAssertNil(outputData.range(of: Data("private redaction test".utf8)))
    }

    func testRenderJPEGStripsAdversarialSourceMetadata() throws {
        let image = try makeSolidImage(width: 4, height: 4, color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        let sourceData = try encodeImageWithPrivateMetadata(image)
        let sourceImage = try decodedImage(from: try imageSource(from: sourceData))

        let outputData = try RedactionRenderer().renderJPEG(redacting: [], in: sourceImage, compressionQuality: 1)
        let outputProperties = try properties(from: try imageSource(from: outputData))
        let outputExif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        XCTAssertNil(outputExif?[kCGImagePropertyExifUserComment])
        XCTAssertNil(outputProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(outputProperties[kCGImagePropertyTIFFDictionary])
        XCTAssertNil(outputProperties[kCGImagePropertyOrientation])
        XCTAssertNil(outputData.range(of: Data("Secret Camera".utf8)))
        XCTAssertNil(outputData.range(of: Data("private redaction test".utf8)))
    }

    func testRenderingDoesNotModifySourceFile() throws {
        let image = try makeSolidImage(width: 4, height: 4, color: CGColor(gray: 1, alpha: 1))
        let sourceData = try encodeImageWithPrivateMetadata(image)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try sourceData.write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let before = try Data(contentsOf: sourceURL)
        let source = try imageSource(from: try Data(contentsOf: sourceURL))
        let outputData = try RedactionRenderer().renderPNG(redacting: [], in: try decodedImage(from: source))
        try outputData.write(to: outputURL)
        let after = try Data(contentsOf: sourceURL)

        XCTAssertEqual(before, after)
        XCTAssertNotEqual(try Data(contentsOf: outputURL), before)
    }

    func testPNGEncodingUsesSameFlattenedBitmapAsRedactedRenderPath() throws {
        let image = try makeSolidImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let detection = Detection(
            kind: .unknown,
            label: "Manual redaction",
            confidence: 1,
            normalizedBounds: CGRect(x: 0.125, y: 0.125, width: 0.50, height: 0.50),
            source: .user,
            reason: "Added by the user.",
            boundsPrecision: .manual
        )
        let renderer = RedactionRenderer()

        let flattenedImage = try renderer.renderImage(redacting: [detection], in: image)
        let encodedFlattened = try renderer.encodePNG(flattenedImage)
        let redactedPNG = try renderer.renderPNG(redacting: [detection], in: image)

        XCTAssertEqual(
            try rgbaPixels(in: try decodedImage(from: try imageSource(from: encodedFlattened))),
            try rgbaPixels(in: try decodedImage(from: try imageSource(from: redactedPNG)))
        )
    }

    func testJPEGEncodingProducesDecodableFlattenedRedaction() throws {
        let image = try makeSolidImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let detection = Detection(
            kind: .unknown,
            label: "Manual redaction",
            confidence: 1,
            normalizedBounds: CGRect(x: 0.25, y: 0.25, width: 0.50, height: 0.50),
            source: .user,
            reason: "Added by the user.",
            boundsPrecision: .manual
        )

        let data = try RedactionRenderer().renderJPEG(redacting: [detection], in: image, compressionQuality: 1)
        let output = try decodedImage(from: try imageSource(from: data))
        let pixels = try rgbaPixels(in: output)
        let redactedPixel = pixel(atX: 4, y: 4, width: output.width, pixels: pixels)

        XCTAssertEqual(output.width, 8)
        XCTAssertEqual(output.height, 8)
        XCTAssertLessThan(redactedPixel.r, 8)
        XCTAssertLessThan(redactedPixel.g, 8)
        XCTAssertLessThan(redactedPixel.b, 8)
    }

    func testOutwardPixelRectFloorsAndCeilsFractionalEdges() {
        let rect = RedactionRenderer.outwardPixelRect(
            for: CGRect(x: 0.1044, y: 0.253, width: 0.1993, height: 0.249),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(rect, CGRect(x: 104, y: 202, width: 200, height: 200))
    }

    func testPreviewPixelRectUsesTopLeftCoordinateSpace() {
        let rect = RedactionRenderer.pixelRect(
            for: CGRect(x: 0.1044, y: 0.253, width: 0.1993, height: 0.249),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(rect.minX, 104.4, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 398.4, accuracy: 0.000001)
        XCTAssertEqual(rect.width, 199.3, accuracy: 0.000001)
        XCTAssertEqual(rect.height, 199.2, accuracy: 0.000001)
    }

    private func makeSolidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
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

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw RedaktrCoreError.imageRenderFailed
        }
        return image
    }

    private func encodeImageWithPrivateMetadata(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        let properties = [
            kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "private redaction test"
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 43.64,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 79.39,
                kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Secret Camera"
            ]
        ] as CFDictionary

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw RedaktrCoreError.imageDestinationFailed
        }

        return data as Data
    }

    private func imageSource(from data: Data) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    }

    private func decodedImage(from source: CGImageSource) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func properties(from source: CGImageSource) throws -> [CFString: Any] {
        try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
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
