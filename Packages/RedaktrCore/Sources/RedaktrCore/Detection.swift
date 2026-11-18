import CoreGraphics
import Foundation

public enum DetectionKind: String, CaseIterable, Sendable {
    case apiKey
    case barcode
    case creditCard
    case email
    case face
    case ipAddress
    case phoneNumber
    case secret
    case unknown
    case url
}

public enum DetectionSource: String, Sendable {
    case deterministic
    case naturalLanguage
    case user
    case vision
}

public enum DetectionSuggestedAction: String, Sendable {
    case redact
    case review
    case ignore
}

public enum DetectionBoundsPrecision: String, Sendable {
    case tight
    case lineFallback
    case manual
    case unknown
}

public struct TextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ nsRange: NSRange) {
        self.init(location: nsRange.location, length: nsRange.length)
    }
}

public struct Detection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: DetectionKind
    public let label: String
    public let confidence: Double
    public let normalizedBounds: CGRect
    public let source: DetectionSource
    public let reason: String
    public let matchedText: String?
    public let matchedRange: TextRange?
    public let suggestedAction: DetectionSuggestedAction
    public let boundsPrecision: DetectionBoundsPrecision
    public let originalNormalizedBounds: CGRect?
    public let originalSource: DetectionSource?
    public let originalReason: String?
    public let originalBoundsPrecision: DetectionBoundsPrecision?

    public init(
        id: UUID = UUID(),
        kind: DetectionKind,
        label: String,
        confidence: Double,
        normalizedBounds: CGRect,
        source: DetectionSource,
        reason: String,
        matchedText: String? = nil,
        matchedRange: TextRange? = nil,
        suggestedAction: DetectionSuggestedAction = .redact,
        boundsPrecision: DetectionBoundsPrecision = .unknown,
        originalNormalizedBounds: CGRect? = nil,
        originalSource: DetectionSource? = nil,
        originalReason: String? = nil,
        originalBoundsPrecision: DetectionBoundsPrecision? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.confidence = confidence
        self.normalizedBounds = normalizedBounds
        self.source = source
        self.reason = reason
        self.matchedText = matchedText
        self.matchedRange = matchedRange
        self.suggestedAction = suggestedAction
        self.boundsPrecision = boundsPrecision
        self.originalNormalizedBounds = originalNormalizedBounds
        self.originalSource = originalSource
        self.originalReason = originalReason
        self.originalBoundsPrecision = originalBoundsPrecision
    }

    public var hasAdjustedBounds: Bool {
        originalNormalizedBounds != nil
    }
}

public struct TextObservation: Sendable {
    public typealias BoundsResolver = @Sendable (NSRange) -> CGRect?

    public let text: String
    public let normalizedBounds: CGRect
    public let confidence: Double
    private let boundsResolver: BoundsResolver?

    public init(
        text: String,
        normalizedBounds: CGRect,
        confidence: Double = 1,
        boundsResolver: BoundsResolver? = nil
    ) {
        self.text = text
        self.normalizedBounds = Self.normalizedImageBounds(normalizedBounds) ?? .zero
        self.confidence = Self.clampedConfidence(confidence)
        self.boundsResolver = boundsResolver
    }

    public func bounds(for range: Range<String.Index>) -> (bounds: CGRect, precision: DetectionBoundsPrecision) {
        let nsRange = NSRange(range, in: text)
        if let resolved = boundsResolver?(nsRange), let normalized = Self.normalizedImageBounds(resolved) {
            return (normalized, .tight)
        }
        return (normalizedBounds, .lineFallback)
    }

    private static func clampedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    private static func normalizedImageBounds(_ bounds: CGRect) -> CGRect? {
        let rect = bounds.standardized
        guard !rect.isNull, !rect.isEmpty, !rect.isInfinite else { return nil }

        if rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 {
            return rect
        }

        let minX = min(max(rect.minX, 0), 1)
        let minY = min(max(rect.minY, 0), 1)
        let maxX = min(max(rect.maxX, 0), 1)
        let maxY = min(max(rect.maxY, 0), 1)

        guard maxX > minX, maxY > minY else { return nil }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

extension TextObservation: Equatable {
    public static func == (lhs: TextObservation, rhs: TextObservation) -> Bool {
        lhs.text == rhs.text
            && lhs.normalizedBounds == rhs.normalizedBounds
            && lhs.confidence == rhs.confidence
    }
}

public enum RedaktrCoreError: Error, Equatable {
    case imageDestinationFailed
    case imageRenderFailed
    case invalidImageData
    case unsupportedImageType
    case textRecognitionFailed
    case visualDetectionFailed
}
