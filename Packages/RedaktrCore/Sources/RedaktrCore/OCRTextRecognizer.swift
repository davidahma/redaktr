import CoreGraphics
import Foundation
import ImageIO
import Vision

public protocol TextRecognizing: Sendable {
    func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [TextObservation]
}

public extension TextRecognizing {
    func recognizeText(in cgImage: CGImage) async throws -> [TextObservation] {
        try await recognizeText(in: cgImage, orientation: .up)
    }
}

public struct OCRTextRecognizer: TextRecognizing {
    private let usesLanguageCorrection: Bool

    public init(usesLanguageCorrection: Bool = true) {
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw RedaktrCoreError.textRecognitionFailed
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation -> TextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            let characterBounds = Self.characterBounds(for: text, candidate: candidate)
            return TextObservation(
                text: text,
                normalizedBounds: observation.boundingBox,
                confidence: Double(candidate.confidence),
                boundsResolver: { nsRange in
                    Self.unionBounds(for: nsRange, in: characterBounds)
                }
            )
        }
    }

    private static func characterBounds(
        for text: String,
        candidate: VNRecognizedText
    ) -> [RecognizedCharacterBounds] {
        var bounds: [RecognizedCharacterBounds] = []
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            defer { index = nextIndex }

            guard !text[index].isWhitespace else { continue }
            let range = index..<nextIndex
            let rectangle = try? candidate.boundingBox(for: range)

            bounds.append(RecognizedCharacterBounds(
                range: TextRange(NSRange(range, in: text)),
                bounds: rectangle?.boundingBox
            ))
        }

        return bounds
    }

    static func unionBounds(
        for nsRange: NSRange,
        in characterBounds: [RecognizedCharacterBounds]
    ) -> CGRect? {
        let requested = TextRange(nsRange)
        let matches = characterBounds.filter { contains($0.range, in: requested) }
        guard !matches.isEmpty else { return nil }

        let rectangles = matches.compactMap(\.bounds)
        guard rectangles.count == matches.count else { return nil }
        return rectangles
            .reduce(CGRect.null) { partialResult, bounds in
                partialResult.union(bounds)
            }
    }

    private static func contains(_ range: TextRange, in container: TextRange) -> Bool {
        let rangeEnd = range.location + range.length
        let containerEnd = container.location + container.length
        return range.location >= container.location && rangeEnd <= containerEnd
    }
}

struct RecognizedCharacterBounds: Sendable {
    let range: TextRange
    let bounds: CGRect?
}
