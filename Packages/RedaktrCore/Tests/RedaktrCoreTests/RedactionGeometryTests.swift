import CoreGraphics
import RedaktrCore
import XCTest

final class RedactionGeometryTests: XCTestCase {
    func testFittedRectCentersResizedPreview() {
        let fitted = RedactionGeometry.fittedRect(
            for: CGSize(width: 400, height: 200),
            in: CGSize(width: 1000, height: 1000)
        )

        assertRect(fitted, equals: CGRect(x: 0, y: 250, width: 1000, height: 500))
    }

    func testDisplayRectMapsImagePixelsIntoRetinaSizedPreview() {
        let imageSize = CGSize(width: 2000, height: 1000)
        let fitted = RedactionGeometry.fittedRect(for: imageSize, in: CGSize(width: 500, height: 500))
        let displayRect = RedactionGeometry.displayRect(
            for: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40),
            imageSize: imageSize,
            fittedRect: fitted
        )

        assertRect(fitted, equals: CGRect(x: 0, y: 125, width: 500, height: 250))
        assertRect(displayRect, equals: CGRect(x: 50, y: 225, width: 150, height: 100))
    }

    func testDisplayRectRoundTripsToNormalizedBounds() {
        let imageSize = CGSize(width: 1200, height: 900)
        let fitted = RedactionGeometry.fittedRect(for: imageSize, in: CGSize(width: 800, height: 500))
        let bounds = CGRect(x: 0.18, y: 0.24, width: 0.36, height: 0.28)
        let displayRect = RedactionGeometry.displayRect(
            for: bounds,
            imageSize: imageSize,
            fittedRect: fitted
        )
        let normalized = RedactionGeometry.normalizedBounds(
            forDisplayRect: displayRect,
            imageSize: imageSize,
            fittedRect: fitted
        )

        assertRect(normalized, equals: bounds)
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
