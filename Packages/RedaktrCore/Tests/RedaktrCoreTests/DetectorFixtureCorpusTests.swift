import CoreGraphics
import Foundation
import RedaktrCore
import XCTest

final class DetectorFixtureCorpusTests: XCTestCase {
    func testFixtureManifestCoversRequiredSurfacesAndUsesSyntheticSources() {
        let requiredSurfaces: Set<String> = [
            "app_ui",
            "cloud_console",
            "dashboard",
            "docs",
            "email",
            "payments",
            "support_tools",
            "terminal"
        ]
        let manifest = Self.textFixtures.map(\.manifestEntry) + Self.visualFixtures.map(\.manifestEntry)
        let surfaces = Set(manifest.map(\.surface))

        XCTAssertTrue(requiredSurfaces.isSubset(of: surfaces))
        XCTAssertTrue(manifest.allSatisfy { $0.sourceType.hasPrefix("synthetic_") })
        XCTAssertTrue(manifest.allSatisfy { !$0.sourceType.contains("real") })
    }

    func testEveryP0DetectorHasPositiveNegativeAndNearMissFixture() {
        let allFixtureIDs = Set(Self.textFixtures.map(\.id) + Self.visualFixtures.map(\.id))
        let positiveLabels = Set((Self.textFixtures.flatMap(\.expected) + Self.visualFixtures.flatMap(\.expected)).map(\.label))
        let absentLabelsByFixture = Dictionary(
            grouping: Self.textFixtures.flatMap { fixture in
                fixture.absentLabels.map { (fixture.id, $0) }
            } + Self.visualFixtures.flatMap { fixture in
                fixture.absentLabels.map { (fixture.id, $0) }
            },
            by: \.0
        )

        for detector in Self.p0DetectorSpecs {
            XCTAssertTrue(positiveLabels.contains(detector.label), "\(detector.label) lacks a positive fixture")
            XCTAssertFalse(detector.negativeFixtureIDs.isEmpty, "\(detector.label) lacks a negative fixture")
            XCTAssertFalse(detector.nearMissFixtureIDs.isEmpty, "\(detector.label) lacks a near-miss fixture")
            XCTAssertTrue(detector.negativeFixtureIDs.allSatisfy(allFixtureIDs.contains))
            XCTAssertTrue(detector.nearMissFixtureIDs.allSatisfy(allFixtureIDs.contains))

            for fixtureID in detector.negativeFixtureIDs + detector.nearMissFixtureIDs {
                let labels = absentLabelsByFixture[fixtureID, default: []].map { $0.1 }
                XCTAssertTrue(labels.contains(detector.label), "\(fixtureID) does not guard \(detector.label)")
            }
        }
    }

    func testDetectorFixtureScorecardMeetsReleaseGate() throws {
        let scorecard = try Self.runScorecard()

        print(scorecard.markdownReport)

        XCTAssertEqual(scorecard.criticalMisses, [])
        XCTAssertEqual(scorecard.falsePositiveControls, [])
        XCTAssertEqual(scorecard.tightnessErrors, [])
        XCTAssertGreaterThan(scorecard.autoOutputEligibleFixtureCount, 0)
        XCTAssertGreaterThan(scorecard.autoOutputReviewFallbackFixtureCount, 0)
        for category in scorecard.categories.values {
            XCTAssertEqual(category.expected, category.found, "\(category.label) recall regressed")
        }
        XCTAssertEqual(scorecard.provisionalReleaseBarStatus, "pass")
    }

    private static func runScorecard() throws -> FixtureScorecard {
        var scorecard = FixtureScorecard()
        let textDetector = SensitiveTextDetector()

        for fixture in textFixtures {
            let detections = textDetector.detections(in: [textObservation(for: fixture)])
            scorecard.record(fixture: fixture, detections: detections)
        }

        for fixture in visualFixtures {
            let detections = VisualSensitiveContentDetector.detections(from: fixture.observations)
            scorecard.record(fixture: fixture, detections: detections)
        }

        return scorecard
    }

    private static func textObservation(for fixture: TextFixture) -> TextObservation {
        let rangeBounds = fixture.expected.compactMap { expected -> (range: NSRange, bounds: CGRect)? in
            guard let matchedText = expected.matchedText else { return nil }
            let range = (fixture.text as NSString).range(of: matchedText)
            guard range.location != NSNotFound else { return nil }
            return (range, expected.bounds)
        }

        return TextObservation(
            text: fixture.text,
            normalizedBounds: fixture.lineBounds,
            boundsResolver: { nsRange in
                rangeBounds.first { NSEqualRanges($0.range, nsRange) }?.bounds
            }
        )
    }
}

private struct ManifestEntry {
    let id: String
    let surface: String
    let sourceType: String
}

private struct DetectorSpec {
    let label: String
    let negativeFixtureIDs: [String]
    let nearMissFixtureIDs: [String]
}

private struct TextFixture {
    let id: String
    let surface: String
    let sourceType = "synthetic_text_observation"
    let text: String
    let expected: [ExpectedDetection]
    let absentLabels: Set<String>
    let lineBounds = CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.80)

    var manifestEntry: ManifestEntry {
        ManifestEntry(id: id, surface: surface, sourceType: sourceType)
    }
}

private struct VisualFixture {
    let id: String
    let surface: String
    let sourceType = "synthetic_visual_observation"
    let observations: [VisualContentObservation]
    let expected: [ExpectedDetection]
    let absentLabels: Set<String>

    var manifestEntry: ManifestEntry {
        ManifestEntry(id: id, surface: surface, sourceType: sourceType)
    }
}

private struct ExpectedDetection {
    let label: String
    let kind: DetectionKind
    let matchedText: String?
    let bounds: CGRect
    let severity: Severity
    let requiresTightBounds: Bool

    init(
        label: String,
        kind: DetectionKind,
        matchedText: String? = nil,
        bounds: CGRect,
        severity: Severity,
        requiresTightBounds: Bool = true
    ) {
        self.label = label
        self.kind = kind
        self.matchedText = matchedText
        self.bounds = bounds
        self.severity = severity
        self.requiresTightBounds = requiresTightBounds
    }
}

private enum Severity {
    case high
    case medium
}

private struct FixtureScorecard {
    struct Category {
        let label: String
        var expected = 0
        var found = 0
    }

    var categories: [String: Category] = [:]
    var criticalMisses: [String] = []
    var falsePositiveControls: [String] = []
    var tightnessErrors: [String] = []
    var autoOutputEligibleFixtureCount = 0
    var autoOutputReviewFallbackFixtureCount = 0

    var provisionalReleaseBarStatus: String {
        criticalMisses.isEmpty && falsePositiveControls.isEmpty && tightnessErrors.isEmpty
            ? "pass"
            : "fail"
    }

    var markdownReport: String {
        let rows = categories.values
            .sorted { $0.label < $1.label }
            .map { category in
                let recall = category.expected == 0
                    ? "n/a"
                    : "\(category.found)/\(category.expected)"
                return "| \(category.label) | \(recall) |"
            }
            .joined(separator: "\n")

        return """

        Detector fixture scorecard
        ==========================
        | Category | Recall |
        | --- | --- |
        \(rows)

        False-positive controls: \(falsePositiveControls.count)
        Tightness errors: \(tightnessErrors.count)
        Critical misses: \(criticalMisses.count)
        Auto-output eligible fixtures: \(autoOutputEligibleFixtureCount)
        Auto-output review fallbacks: \(autoOutputReviewFallbackFixtureCount)
        Provisional release bar: \(provisionalReleaseBarStatus)
        """
    }

    mutating func record(fixture: TextFixture, detections: [Detection]) {
        record(
            fixtureID: fixture.id,
            expected: fixture.expected,
            absentLabels: fixture.absentLabels,
            detections: detections
        )
    }

    mutating func record(fixture: VisualFixture, detections: [Detection]) {
        record(
            fixtureID: fixture.id,
            expected: fixture.expected,
            absentLabels: fixture.absentLabels,
            detections: detections
        )
    }

    private mutating func record(
        fixtureID: String,
        expected: [ExpectedDetection],
        absentLabels: Set<String>,
        detections: [Detection]
    ) {
        recordAutoOutputGate(detections: detections)

        for expectedDetection in expected {
            categories[expectedDetection.label, default: Category(label: expectedDetection.label)].expected += 1
            guard let detection = matchingDetection(for: expectedDetection, in: detections) else {
                if expectedDetection.severity == .high {
                    criticalMisses.append("\(fixtureID): \(expectedDetection.label)")
                }
                continue
            }

            categories[expectedDetection.label, default: Category(label: expectedDetection.label)].found += 1
            if expectedDetection.requiresTightBounds && detection.boundsPrecision != .tight {
                tightnessErrors.append("\(fixtureID): \(expectedDetection.label) used \(detection.boundsPrecision.rawValue)")
            }
            if detection.normalizedBounds != expectedDetection.bounds {
                tightnessErrors.append("\(fixtureID): \(expectedDetection.label) bounds \(detection.normalizedBounds) expected \(expectedDetection.bounds)")
            }
        }

        for detection in detections where absentLabels.contains(detection.label) {
            falsePositiveControls.append("\(fixtureID): \(detection.label)")
        }
    }

    private mutating func recordAutoOutputGate(detections: [Detection]) {
        let activeDetections = detections.filter { $0.suggestedAction != .ignore }
        guard !activeDetections.isEmpty else { return }

        let requiresReview = activeDetections.contains { detection in
            detection.suggestedAction == .review
                || detection.confidence < 0.8
                || detection.boundsPrecision == .lineFallback
        }
        if requiresReview {
            autoOutputReviewFallbackFixtureCount += 1
        } else {
            autoOutputEligibleFixtureCount += 1
        }
    }

    private func matchingDetection(
        for expected: ExpectedDetection,
        in detections: [Detection]
    ) -> Detection? {
        detections.first { detection in
            guard detection.label == expected.label, detection.kind == expected.kind else { return false }
            if let matchedText = expected.matchedText {
                return detection.matchedText == matchedText
            }
            return true
        }
    }
}

private extension DetectorFixtureCorpusTests {
    static let p0DetectorSpecs: [DetectorSpec] = [
        DetectorSpec(label: "AWS key", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["cloud-near-miss-controls"]),
        DetectorSpec(label: "Barcode", negativeFixtureIDs: ["visual-safe-controls"], nearMissFixtureIDs: ["visual-near-miss-controls"]),
        DetectorSpec(label: "Bearer token", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["terminal-near-miss-controls"]),
        DetectorSpec(label: "Card number", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["payments-near-miss-controls"]),
        DetectorSpec(label: "Email", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["docs-near-miss-controls"]),
        DetectorSpec(label: "Environment secret", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["terminal-near-miss-controls"]),
        DetectorSpec(label: "Face", negativeFixtureIDs: ["visual-safe-controls"], nearMissFixtureIDs: ["visual-near-miss-controls"]),
        DetectorSpec(label: "GitHub token", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["terminal-near-miss-controls"]),
        DetectorSpec(label: "Google API key", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["cloud-near-miss-controls"]),
        DetectorSpec(label: "High-entropy secret", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["docs-near-miss-controls"]),
        DetectorSpec(label: "IP address", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["docs-near-miss-controls"]),
        DetectorSpec(label: "JWT", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["terminal-near-miss-controls"]),
        DetectorSpec(label: "OpenAI API key", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["cloud-near-miss-controls"]),
        DetectorSpec(label: "Phone number", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["docs-near-miss-controls"]),
        DetectorSpec(label: "QR code", negativeFixtureIDs: ["visual-safe-controls"], nearMissFixtureIDs: ["visual-near-miss-controls"]),
        DetectorSpec(label: "Slack token", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["support-near-miss-controls"]),
        DetectorSpec(label: "Stripe secret key", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["payments-near-miss-controls"]),
        DetectorSpec(label: "URL query token", negativeFixtureIDs: ["docs-safe-controls"], nearMissFixtureIDs: ["app-near-miss-controls"])
    ]

    static let textFixtures: [TextFixture] = [
        TextFixture(
            id: "terminal-secrets",
            surface: "terminal",
            text: """
            export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
            gh auth token ghp_1234567890abcdefghijklMNOPQR
            Authorization: Bearer tokenValue123ABCdef456
            jwt=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.Signature123
            DATABASE_PASSWORD=correctHorse9Battery!
            nonce aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK
            """,
            expected: [
                ExpectedDetection(label: "AWS key", kind: .apiKey, matchedText: "AKIAIOSFODNN7EXAMPLE", bounds: CGRect(x: 0.11, y: 0.78, width: 0.18, height: 0.04), severity: .high),
                ExpectedDetection(label: "GitHub token", kind: .apiKey, matchedText: "ghp_1234567890abcdefghijklMNOPQR", bounds: CGRect(x: 0.12, y: 0.67, width: 0.30, height: 0.04), severity: .high),
                ExpectedDetection(label: "Bearer token", kind: .secret, matchedText: "Bearer tokenValue123ABCdef456", bounds: CGRect(x: 0.18, y: 0.56, width: 0.28, height: 0.04), severity: .high),
                ExpectedDetection(label: "JWT", kind: .secret, matchedText: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.Signature123", bounds: CGRect(x: 0.10, y: 0.45, width: 0.42, height: 0.04), severity: .high),
                ExpectedDetection(label: "Environment secret", kind: .secret, matchedText: "correctHorse9Battery!", bounds: CGRect(x: 0.19, y: 0.34, width: 0.22, height: 0.04), severity: .high),
                ExpectedDetection(label: "High-entropy secret", kind: .secret, matchedText: "aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK", bounds: CGRect(x: 0.12, y: 0.23, width: 0.32, height: 0.04), severity: .medium)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "dashboard-customer-table",
            surface: "dashboard",
            text: "Customer row customer_01HZYXWVUTSRQPONMLKJIHGFED: sam@example.com opened ticket from 10.10.12.8",
            expected: [
                ExpectedDetection(label: "Account/customer ID", kind: .unknown, matchedText: "customer_01HZYXWVUTSRQPONMLKJIHGFED", bounds: CGRect(x: 0.12, y: 0.62, width: 0.34, height: 0.05), severity: .medium),
                ExpectedDetection(label: "Email", kind: .email, matchedText: "sam@example.com", bounds: CGRect(x: 0.20, y: 0.62, width: 0.18, height: 0.05), severity: .high),
                ExpectedDetection(label: "IP address", kind: .ipAddress, matchedText: "10.10.12.8", bounds: CGRect(x: 0.67, y: 0.62, width: 0.12, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "email-thread",
            surface: "email",
            text: "Reply to Alex at alex.builder@example.co before 3pm.",
            expected: [
                ExpectedDetection(label: "Email", kind: .email, matchedText: "alex.builder@example.co", bounds: CGRect(x: 0.27, y: 0.60, width: 0.22, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "payments-receipt",
            surface: "payments",
            text: "Stripe key sk_live_1234567890abcdef123456 and card 4242 4242 4242 4242",
            expected: [
                ExpectedDetection(label: "Stripe secret key", kind: .apiKey, matchedText: "sk_live_1234567890abcdef123456", bounds: CGRect(x: 0.18, y: 0.60, width: 0.30, height: 0.05), severity: .high),
                ExpectedDetection(label: "Card number", kind: .creditCard, matchedText: "4242 4242 4242 4242", bounds: CGRect(x: 0.62, y: 0.60, width: 0.22, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "cloud-console-keys",
            surface: "cloud_console",
            text: "Google AIzaSyA1234567890abcdefGHIJKLMNopqrsTuv OpenAI sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz1234567890",
            expected: [
                ExpectedDetection(label: "Google API key", kind: .apiKey, matchedText: "AIzaSyA1234567890abcdefGHIJKLMNopqrsTuv", bounds: CGRect(x: 0.16, y: 0.60, width: 0.36, height: 0.05), severity: .high),
                ExpectedDetection(label: "OpenAI API key", kind: .apiKey, matchedText: "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz1234567890", bounds: CGRect(x: 0.61, y: 0.60, width: 0.34, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "support-contact",
            surface: "support_tools",
            text: "Slack \(SyntheticDetectorValues.slackBotToken) call +1 (415) 555-0134",
            expected: [
                ExpectedDetection(label: "Slack token", kind: .apiKey, matchedText: SyntheticDetectorValues.slackBotToken, bounds: CGRect(x: 0.12, y: 0.60, width: 0.38, height: 0.05), severity: .high),
                ExpectedDetection(label: "Phone number", kind: .phoneNumber, matchedText: "+1 (415) 555-0134", bounds: CGRect(x: 0.58, y: 0.60, width: 0.18, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "app-ui-url-token",
            surface: "app_ui",
            text: "Callback https://example.com/callback?access_token=urlToken1234567890abcdef&state=ok",
            expected: [
                ExpectedDetection(label: "URL query token", kind: .url, matchedText: "urlToken1234567890abcdef", bounds: CGRect(x: 0.55, y: 0.60, width: 0.24, height: 0.05), severity: .high)
            ],
            absentLabels: []
        ),
        TextFixture(
            id: "docs-safe-controls",
            surface: "docs",
            text: """
            Order ORDER-20260617-00012345 shipped at 2026-06-17 09:36:34.
            Public UUID 550e8400-e29b-41d4-a716-446655440000.
            CUSTOMER_ID=customer_01HZYXWVUTSRQPONMLKJIHGFED.
            Bare digits 4155550134 should not be enough.
            """,
            expected: [],
            absentLabels: Set(p0DetectorSpecs.map(\.label))
        ),
        TextFixture(
            id: "terminal-near-miss-controls",
            surface: "terminal",
            text: """
            ghp_short
            Bear tokenValue123ABCdef456
            eyJ.not-enough
            API_KEY=changeme
            """,
            expected: [],
            absentLabels: ["Bearer token", "Environment secret", "GitHub token", "JWT"]
        ),
        TextFixture(
            id: "cloud-near-miss-controls",
            surface: "cloud_console",
            text: "AWS AKIA123 Google AIzaShort OpenAI sk-proj-short",
            expected: [],
            absentLabels: ["AWS key", "Google API key", "OpenAI API key"]
        ),
        TextFixture(
            id: "payments-near-miss-controls",
            surface: "payments",
            text: "Stripe publishable pk_live_1234567890abcdef invalid card 4242 4242 4242 4241",
            expected: [],
            absentLabels: ["Card number", "Stripe secret key"]
        ),
        TextFixture(
            id: "docs-near-miss-controls",
            surface: "docs",
            text: "Email sam@example phone 4155550134 IP 999.10.12.8 random customer_01HZYXWVUTSRQPONMLKJIHGFED",
            expected: [],
            absentLabels: ["Email", "High-entropy secret", "IP address", "Phone number"]
        ),
        TextFixture(
            id: "app-near-miss-controls",
            surface: "app_ui",
            text: "Open https://example.com/callback?state=ok&query=public",
            expected: [],
            absentLabels: ["URL query token"]
        ),
        TextFixture(
            id: "support-near-miss-controls",
            surface: "support_tools",
            text: "Slack placeholder xoxb-short should not redact.",
            expected: [],
            absentLabels: ["Slack token"]
        )
    ]

    static let visualFixtures: [VisualFixture] = [
        VisualFixture(
            id: "visual-face-and-qr",
            surface: "support_tools",
            observations: [
                VisualContentObservation(kind: .face, normalizedBounds: CGRect(x: 0.12, y: 0.44, width: 0.18, height: 0.28), confidence: 0.92),
                VisualContentObservation(kind: .qrCode, normalizedBounds: CGRect(x: 0.72, y: 0.20, width: 0.16, height: 0.16), confidence: 0.96, symbology: "QR")
            ],
            expected: [
                ExpectedDetection(label: "Face", kind: .face, bounds: CGRect(x: 0.12, y: 0.44, width: 0.18, height: 0.28), severity: .high),
                ExpectedDetection(label: "QR code", kind: .barcode, bounds: CGRect(x: 0.72, y: 0.20, width: 0.16, height: 0.16), severity: .high)
            ],
            absentLabels: []
        ),
        VisualFixture(
            id: "visual-shipping-barcode",
            surface: "payments",
            observations: [
                VisualContentObservation(kind: .barcode, normalizedBounds: CGRect(x: 0.36, y: 0.18, width: 0.42, height: 0.12), confidence: 0.89, symbology: "Code128")
            ],
            expected: [
                ExpectedDetection(label: "Barcode", kind: .barcode, bounds: CGRect(x: 0.36, y: 0.18, width: 0.42, height: 0.12), severity: .high)
            ],
            absentLabels: []
        ),
        VisualFixture(
            id: "visual-safe-controls",
            surface: "docs",
            observations: [],
            expected: [],
            absentLabels: ["Barcode", "Face", "QR code"]
        ),
        VisualFixture(
            id: "visual-near-miss-controls",
            surface: "app_ui",
            observations: [],
            expected: [],
            absentLabels: ["Barcode", "Face", "QR code"]
        )
    ]
}
