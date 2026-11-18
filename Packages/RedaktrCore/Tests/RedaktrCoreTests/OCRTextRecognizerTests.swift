import CoreGraphics
import ImageIO
import RedaktrCore
import XCTest

final class OCRTextRecognizerTests: XCTestCase {
    func testRecognizeTextCanRunAcrossBatchImagesWithoutContinuationTrap() async throws {
        let recognizer = OCRTextRecognizer()
        let images = try (0..<4).map { _ in try makeTestImage(width: 96, height: 64) }

        for image in images {
            let observations = try await recognizer.recognizeText(in: image, orientation: .up)
            XCTAssertEqual(observations, [])
        }
    }

    func testRecognizerCanRunWithLanguageCorrectionDisabledForFidelityExperiments() async throws {
        let recognizer = OCRTextRecognizer(usesLanguageCorrection: false)
        let image = try makeTestImage(width: 96, height: 64)

        let observations = try await recognizer.recognizeText(in: image, orientation: .up)

        XCTAssertEqual(observations, [])
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

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw RedaktrCoreError.imageRenderFailed
        }
        return image
    }
}
