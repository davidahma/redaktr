import CoreGraphics
import ImageIO
import RedaktrCore
import XCTest

final class VisualSensitiveContentDetectorTests: XCTestCase {
    func testMapsFaceObservationToRedactionDetection() throws {
        let bounds = CGRect(x: 0.18, y: 0.52, width: 0.24, height: 0.28)
        let detections = VisualSensitiveContentDetector.detections(from: [
            VisualContentObservation(
                kind: .face,
                normalizedBounds: bounds,
                confidence: 0.91
            )
        ])

        let face = try XCTUnwrap(detections.first)
        XCTAssertEqual(face.kind, .face)
        XCTAssertEqual(face.label, "Face")
        XCTAssertEqual(face.confidence, 0.91)
        XCTAssertEqual(face.normalizedBounds, bounds)
        XCTAssertEqual(face.source, .vision)
        XCTAssertEqual(face.suggestedAction, .redact)
        XCTAssertEqual(face.boundsPrecision, .tight)
        XCTAssertNil(face.matchedText)
        XCTAssertNil(face.matchedRange)
    }

    func testMapsQRCodeAndBarcodeObservationsToRedactionDetections() {
        let detections = VisualSensitiveContentDetector.detections(from: [
            VisualContentObservation(
                kind: .qrCode,
                normalizedBounds: CGRect(x: 0.10, y: 0.15, width: 0.12, height: 0.12),
                confidence: 0.96,
                symbology: "QR"
            ),
            VisualContentObservation(
                kind: .barcode,
                normalizedBounds: CGRect(x: 0.55, y: 0.18, width: 0.30, height: 0.10),
                confidence: 0.88,
                symbology: "Code128"
            )
        ])

        XCTAssertTrue(detections.contains { detection in
            detection.kind == .barcode
                && detection.label == "QR code"
                && detection.suggestedAction == .redact
                && detection.source == .vision
        })
        XCTAssertTrue(detections.contains { detection in
            detection.kind == .barcode
                && detection.label == "Barcode"
                && detection.suggestedAction == .redact
                && detection.source == .vision
        })
    }

    func testDetectorCategoryPreferencesSuppressVisualFamilies() {
        var preferences = DetectorCategoryPreferences.allEnabled
        preferences.setEnabled(false, for: .visualCodes)
        let detections = VisualSensitiveContentDetector.detections(
            from: [
                VisualContentObservation(
                    kind: .qrCode,
                    normalizedBounds: CGRect(x: 0.10, y: 0.15, width: 0.12, height: 0.12),
                    confidence: 0.96,
                    symbology: "QR"
                ),
                VisualContentObservation(
                    kind: .face,
                    normalizedBounds: CGRect(x: 0.55, y: 0.18, width: 0.20, height: 0.20),
                    confidence: 0.88
                )
            ],
            preferences: preferences
        )

        XCTAssertFalse(detections.contains { $0.kind == .barcode })
        XCTAssertTrue(detections.contains { $0.kind == .face })
    }

    func testClampsVisionConfidenceIntoValidRange() throws {
        let detections = VisualSensitiveContentDetector.detections(from: [
            VisualContentObservation(
                kind: .barcode,
                normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
                confidence: 1.4
            ),
            VisualContentObservation(
                kind: .face,
                normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                confidence: -0.2
            )
        ])

        XCTAssertEqual(detections.first { $0.label == "Barcode" }?.confidence, 1)
        XCTAssertEqual(detections.first { $0.label == "Face" }?.confidence, 0)
    }

    func testRedactionPlanCombinesTextAndVisualDetections() {
        let text = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.9,
            normalizedBounds: CGRect(x: 0.10, y: 0.82, width: 0.20, height: 0.06),
            source: .deterministic,
            reason: "Email addresses can identify a person or account.",
            matchedText: "sam@example.com",
            matchedRange: TextRange(location: 8, length: 15),
            boundsPrecision: .tight
        )
        let visual = VisualSensitiveContentDetector.detections(from: [
            VisualContentObservation(
                kind: .face,
                normalizedBounds: CGRect(x: 0.62, y: 0.42, width: 0.18, height: 0.24),
                confidence: 0.94
            )
        ])

        let plan = RedactionPlan(textDetections: [text], visionDetections: visual)

        XCTAssertEqual(plan.detections.count, 2)
        XCTAssertTrue(plan.detections.contains { $0.kind == .email })
        XCTAssertTrue(plan.detections.contains { $0.kind == .face })
        XCTAssertEqual(plan.activeDetections.count, 2)
    }

    func testMockVisualDetectorProtocolSeamCanInjectDetections() async throws {
        let expected = Detection(
            id: UUID(uuidString: "2C04AB6C-A4E0-4588-AE23-D67E0BB26E6A")!,
            kind: .barcode,
            label: "QR code",
            confidence: 0.95,
            normalizedBounds: CGRect(x: 0.2, y: 0.2, width: 0.18, height: 0.18),
            source: .vision,
            reason: "QR codes can encode URLs, tokens, or contact details.",
            boundsPrecision: .tight
        )
        let detector = MockVisualDetector(detectionsToReturn: [expected])
        let image = try makeTestImage(width: 4, height: 4)

        let detections = try await detector.detections(in: image, orientation: .right)

        XCTAssertEqual(detections, [expected])
    }

    func testDefaultProtocolEntryPointUsesUpOrientation() async throws {
        let expected = Detection(
            id: UUID(uuidString: "B50D1388-F6C3-4A48-9B83-563AFB9B9E06")!,
            kind: .face,
            label: "Face",
            confidence: 0.91,
            normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
            source: .vision,
            reason: "Faces can identify people in shared screenshots.",
            boundsPrecision: .tight
        )
        let detector = OrientationAssertingVisualDetector(expectedOrientation: .up, detectionsToReturn: [expected])
        let image = try makeTestImage(width: 4, height: 4)

        let detections = try await detector.detections(in: image)

        XCTAssertEqual(detections, [expected])
    }

    func testLiveVisualDetectorReturnsNoDetectionsForBlankImage() async throws {
        let image = try makeTestImage(width: 64, height: 64)

        let detections = try await VisualSensitiveContentDetector().detections(in: image, orientation: .up)

        XCTAssertEqual(detections, [])
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

private struct MockVisualDetector: VisualContentDetecting {
    let detectionsToReturn: [Detection]

    func detections(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [Detection] {
        detectionsToReturn
    }
}

private struct OrientationAssertingVisualDetector: VisualContentDetecting {
    let expectedOrientation: CGImagePropertyOrientation
    let detectionsToReturn: [Detection]

    func detections(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [Detection] {
        XCTAssertEqual(orientation, expectedOrientation)
        return detectionsToReturn
    }
}
