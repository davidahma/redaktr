import CoreGraphics
import CoreImage
import CoreText
import Foundation
import RedaktrCore
import XCTest

/// Fixture geometry is defined in the drawing code. Vision sees only the raster.
final class VisionCorpusTests: XCTestCase {
    func testSupportScreenshotMasksEmailAndPreservesControlThroughPNGAndJPEG() async throws {
        let email = "maya@example.com"
        let control = "Release notes"
        let context = try makeContext()
        draw(email, at: CGPoint(x: 55, y: 250), in: context)
        draw(control, at: CGPoint(x: 55, y: 128), in: context)
        let source = try XCTUnwrap(context.makeImage())
        let renderer = RedactionRenderer()
        let imported = try ImageImporter.importImage(from: renderer.encodePNG(source))
        let recognizer = OCRTextRecognizer()
        let originalText = try await recognizer.recognizeText(in: imported.cgImage, orientation: imported.orientation)
        XCTAssertTrue(originalText.contains { $0.text == email })
        XCTAssertTrue(originalText.contains { $0.text == control })

        let detections = SensitiveTextDetector().detections(in: originalText)
        XCTAssertEqual(detections.map(\.kind), [.email])
        let masks = RedactionPlan(textDetections: detections).activeDetections
        let witness = CGPoint(x: 96, y: 269)
        let safeRegion = CGRect(x: 35, y: 105, width: 340, height: 80)

        let outputs = try [
            renderer.renderPNG(redacting: masks, in: imported.cgImage),
            renderer.renderJPEG(redacting: masks, in: imported.cgImage)
        ]
        for output in outputs {
            let decoded = try ImageImporter.importImage(from: output).cgImage
            let outputText = try await recognizer.recognizeText(in: decoded)
            XCTAssertFalse(outputText.contains { $0.text.localizedCaseInsensitiveContains("example.com") })
            XCTAssertTrue(outputText.contains { $0.text == control })
            XCTAssertEqual(try pixel(at: witness, in: decoded), [0, 0, 0, 255])
        }
        let png = try ImageImporter.importImage(from: outputs[0]).cgImage
        XCTAssertEqual(try pixels(in: safeRegion, of: png), try pixels(in: safeRegion, of: source))
    }

    func testQRFixtureIsMaskedAndUnrelatedTextIsPreserved() async throws {
        let context = try makeContext()
        let codeRect = CGRect(x: 55, y: 155, width: 170, height: 170)
        let generator = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        generator.setValue(Data("https://example.invalid/support".utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(generator.outputImage)
        let code = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        context.interpolationQuality = .none
        context.draw(code, in: codeRect)
        draw("Release notes", at: CGPoint(x: 285, y: 215), in: context)
        let original = try XCTUnwrap(context.makeImage())

        let detector = VisualSensitiveContentDetector()
        let findings = try await detector.detections(in: original)
        XCTAssertEqual(findings.map(\.label), ["QR code"])
        let masks = RedactionPlan(visionDetections: findings).activeDetections
        let outputPNG = try RedactionRenderer().renderPNG(redacting: masks, in: original)
        let decoded = try ImageImporter.importImage(from: outputPNG).cgImage
        let remaining = try await detector.detections(in: decoded)
        XCTAssertTrue(remaining.isEmpty)
        let centerRegion = codeRect.insetBy(dx: 30, dy: 30)
        XCTAssertEqual(
            try pixels(in: centerRegion, of: decoded),
            Array(repeating: [UInt8(0), 0, 0, 255], count: Int(centerRegion.width * centerRegion.height)).flatMap { $0 }
        )
        let safeRegion = CGRect(x: 270, y: 190, width: 390, height: 75)
        XCTAssertEqual(try pixels(in: safeRegion, of: decoded), try pixels(in: safeRegion, of: original))
    }

    private func makeContext() throws -> CGContext {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 720, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context
    }

    private func draw(_ text: String, at origin: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, 38, nil),
            .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0.2, alpha: 1)
        ]
        context.textPosition = origin
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }

    private func pixel(at point: CGPoint, in image: CGImage) throws -> [UInt8] {
        try pixels(in: CGRect(origin: point, size: CGSize(width: 1, height: 1)), of: image)
    }

    private func pixels(in rect: CGRect, of image: CGImage) throws -> [UInt8] {
        let topOrigin = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height)
        let cropped = try XCTUnwrap(image.cropping(to: topOrigin))
        let width = cropped.width
        let height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
}
