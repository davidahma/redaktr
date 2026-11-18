import CoreGraphics
import RedaktrCore
import XCTest

final class TextObservationTests: XCTestCase {
    func testTextObservationNormalizesBoundsAndClampsConfidence() {
        let observation = TextObservation(
            text: "Contact sam@example.com",
            normalizedBounds: CGRect(x: -0.10, y: 0.25, width: 0.40, height: 0.90),
            confidence: 1.4
        )

        assertRect(
            observation.normalizedBounds,
            equals: CGRect(x: 0, y: 0.25, width: 0.30, height: 0.75)
        )
        XCTAssertEqual(observation.confidence, 1)
    }

    func testSubstringBoundsResolverNormalizesTightBoundsAndFallsBackToLine() throws {
        let text = "Prefix sam@example.com suffix"
        let emailRange = (text as NSString).range(of: "sam@example.com")
        let prefixRange = (text as NSString).range(of: "Prefix")
        let lineBounds = CGRect(x: 0.10, y: 0.60, width: 0.80, height: 0.10)
        let observation = TextObservation(
            text: text,
            normalizedBounds: lineBounds,
            confidence: 0.88,
            boundsResolver: { nsRange in
                nsRange == emailRange
                    ? CGRect(x: 0.32, y: -0.10, width: 0.22, height: 0.18)
                    : .zero
            }
        )

        let emailBounds = observation.bounds(for: try XCTUnwrap(Range(emailRange, in: text)))
        assertRect(
            emailBounds.bounds,
            equals: CGRect(x: 0.32, y: 0, width: 0.22, height: 0.08)
        )
        XCTAssertEqual(emailBounds.precision, .tight)

        let prefixBounds = observation.bounds(for: try XCTUnwrap(Range(prefixRange, in: text)))
        XCTAssertEqual(prefixBounds.bounds, lineBounds)
        XCTAssertEqual(prefixBounds.precision, .lineFallback)
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}
