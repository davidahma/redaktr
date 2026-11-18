import CoreGraphics
import Foundation
import ImageIO
import Vision

public protocol VisualContentDetecting: Sendable {
    func detections(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [Detection]
}

public extension VisualContentDetecting {
    func detections(in cgImage: CGImage) async throws -> [Detection] {
        try await detections(in: cgImage, orientation: .up)
    }
}

public struct VisualContentObservation: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case barcode
        case face
        case qrCode
    }

    public let kind: Kind
    public let normalizedBounds: CGRect
    public let confidence: Double
    public let symbology: String?

    public init(
        kind: Kind,
        normalizedBounds: CGRect,
        confidence: Double,
        symbology: String? = nil
    ) {
        self.kind = kind
        self.normalizedBounds = normalizedBounds
        self.confidence = confidence
        self.symbology = symbology
    }
}

public struct VisualSensitiveContentDetector: VisualContentDetecting {
    public init() {}

    public func detections(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [Detection] {
        try await detections(in: cgImage, orientation: orientation, preferences: .allEnabled)
    }

    public func detections(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        preferences: DetectorCategoryPreferences
    ) async throws -> [Detection] {
        let observations = try Self.observations(in: cgImage, orientation: orientation)
        return Self.detections(from: observations, preferences: preferences)
    }

    public static func detections(from observations: [VisualContentObservation]) -> [Detection] {
        detections(from: observations, preferences: .allEnabled)
    }

    public static func detections(
        from observations: [VisualContentObservation],
        preferences: DetectorCategoryPreferences
    ) -> [Detection] {
        observations.compactMap { observation in
            let metadata = detectionMetadata(for: observation)
            let category: DetectorCategory = observation.kind == .face ? .faces : .visualCodes
            let disposition = preferences.resolvedDisposition(
                for: category, detectorLabel: metadata.label, defaultDisposition: .autoRedact
            )
            guard disposition != .ignore else { return nil }
            return Detection(
                kind: metadata.kind,
                label: metadata.label,
                confidence: clampedConfidence(observation.confidence),
                normalizedBounds: observation.normalizedBounds,
                source: .vision,
                reason: metadata.reason,
                suggestedAction: disposition.suggestedAction,
                boundsPrecision: .tight
            )
        }
    }

    private static func observations(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> [VisualContentObservation] {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let barcodeRequest = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([faceRequest, barcodeRequest])
        } catch {
            throw RedaktrCoreError.visualDetectionFailed
        }

        let faces = (faceRequest.results ?? []).map { observation in
            VisualContentObservation(
                kind: .face,
                normalizedBounds: observation.boundingBox,
                confidence: Double(observation.confidence)
            )
        }

        let barcodes = (barcodeRequest.results ?? []).map { observation in
            let symbology = String(describing: observation.symbology)
            return VisualContentObservation(
                kind: isQRCode(symbology: symbology) ? .qrCode : .barcode,
                normalizedBounds: observation.boundingBox,
                confidence: Double(observation.confidence),
                symbology: symbology
            )
        }

        return faces + barcodes
    }

    private static func detectionMetadata(
        for observation: VisualContentObservation
    ) -> (kind: DetectionKind, label: String, reason: String) {
        switch observation.kind {
        case .face:
            return (
                .face,
                "Face",
                "Faces can identify people in shared screenshots."
            )
        case .qrCode:
            return (
                .barcode,
                "QR code",
                "QR codes can encode URLs, tokens, or contact details."
            )
        case .barcode:
            return (
                .barcode,
                "Barcode",
                "Barcodes can reveal shipment, product, or account identifiers."
            )
        }
    }

    private static func isQRCode(symbology: String) -> Bool {
        symbology.localizedCaseInsensitiveContains("qr")
    }

    private static func clampedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }
}
