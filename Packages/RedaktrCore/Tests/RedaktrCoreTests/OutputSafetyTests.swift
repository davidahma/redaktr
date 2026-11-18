import AppKit
@testable import RedaktrCore
import XCTest

final class OutputSafetyTests: XCTestCase {
    func testOnlyCompletedOrExplicitlyReviewedScansAllowOutput() {
        for state in [ImageScanState.queued, .scanning, .failed, .cancelled] {
            XCTAssertFalse(state.allowsOutput)
        }
        XCTAssertTrue(ImageScanState.succeeded.allowsOutput)
        XCTAssertTrue(ImageScanState.manuallyReviewed.allowsOutput)
    }

    func testOnlyCompleteCharacterGeometryIsTight() {
        let first = CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.2)
        let last = CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.2)
        let firstRange = TextRange(location: 0, length: 1)
        let lastRange = TextRange(location: 1, length: 1)
        let range = NSRange(location: 0, length: 2)
        let partial = [RecognizedCharacterBounds(range: firstRange, bounds: first),
                       RecognizedCharacterBounds(range: lastRange, bounds: nil)]
        XCTAssertNil(OCRTextRecognizer.unionBounds(for: range, in: partial))
        let complete = [partial[0], RecognizedCharacterBounds(range: lastRange, bounds: last)]
        XCTAssertEqual(OCRTextRecognizer.unionBounds(for: range, in: complete), first.union(last))
    }

    func testSourceIdentityRecognizesSymlinkHardLinkAndMovedSource() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("source.png")
        let link = root.appendingPathComponent("link.png")
        let hardLink = root.appendingPathComponent("hardlink.png")
        let moved = root.appendingPathComponent("renamed.png")
        try Data([7]).write(to: original)
        let source = SourceFileIdentity(original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        try FileManager.default.linkItem(at: original, to: hardLink)
        XCTAssertTrue(source.matches(link))
        XCTAssertTrue(source.matches(hardLink))
        XCTAssertFalse(source.matches(moved))
        try FileManager.default.moveItem(at: original, to: moved)
        XCTAssertTrue(source.matches(moved))
        try Data([8]).write(to: original)
        XCTAssertTrue(source.matches(original))
        XCTAssertFalse(source.isSameExistingFile(as: original))
    }

    func testBatchPublishesOnlyCompleteDirectoryAndPreservesEarlierExports() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try BatchOutputWriter.write(in: root) { stage in
            try Data([1]).write(to: stage.appendingPathComponent("one.png"))
        }
        XCTAssertThrowsError(try BatchOutputWriter.write(in: root) { stage in
            try Data([2]).write(to: stage.appendingPathComponent("partial.png"))
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [first.lastPathComponent])
        let second = try BatchOutputWriter.write(in: root) { stage in
            try Data([3]).write(to: stage.appendingPathComponent("two.png"))
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("one.png")), Data([1]))
        XCTAssertEqual(try Data(contentsOf: second.appendingPathComponent("two.png")), Data([3]))
    }

    func testVisualRuleUsesDetectorThenCategoryDisposition() throws {
        let qr = VisualContentObservation(kind: .qrCode, normalizedBounds: .init(x: 0.1, y: 0.1, width: 0.3, height: 0.3), confidence: 1)
        let face = VisualContentObservation(kind: .face, normalizedBounds: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 1)
        var preferences = DetectorCategoryPreferences(categoryDispositions: [.visualCodes: .ignore, .faces: .needsReview])
        preferences.setDisposition(.needsReview, forDetectorLabel: "QR code")
        let findings = VisualSensitiveContentDetector.detections(from: [qr, face], preferences: preferences)
        XCTAssertEqual(findings.map(\.suggestedAction), [.review, .review])
        preferences.setDisposition(.ignore, forDetectorLabel: "Face")
        XCTAssertEqual(VisualSensitiveContentDetector.detections(from: [qr, face], preferences: preferences).map(\.label), ["QR code"])
    }

    @MainActor
    func testClipboardReplacementAndUndoRespectTheOwnersGeneration() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("first", forType: .string)
        let first = ClipboardUndoSnapshot.capture(from: board)
        board.clearContents()
        board.setString("second", forType: .string)
        XCTAssertNil(try first.replace(with: Data([1]), in: board))
        XCTAssertEqual(board.string(forType: .string), "second")
        let second = ClipboardUndoSnapshot.capture(from: board)
        let owned = try XCTUnwrap(second.replace(with: Data([2]), in: board))
        XCTAssertEqual(owned, board.changeCount)
        XCTAssertTrue(second.restore(to: board, ifOwnedGeneration: owned))
        XCTAssertEqual(board.string(forType: .string), "second")
        let third = ClipboardUndoSnapshot.capture(from: board)
        let stale = try XCTUnwrap(third.replace(with: Data([3]), in: board))
        board.clearContents()
        board.setString("newer", forType: .string)
        XCTAssertFalse(third.restore(to: board, ifOwnedGeneration: stale))
        XCTAssertEqual(board.string(forType: .string), "newer")
    }

    func testBatchAdmissionRejectsCountPixelAndOverflowBeforeDecoding() throws {
        var budget = ImageBatchBudget()
        try budget.reserve(width: 8_000, height: 8_000)
        XCTAssertThrowsError(try budget.reserve(width: 1, height: 1))
        var files = ImageBatchBudget()
        XCTAssertThrowsError(try files.reserve(width: Int.max, height: Int.max))
        for _ in 0..<ImageBatchBudget.maximumFileCount { try files.reserve(width: 1, height: 1) }
        XCTAssertThrowsError(try files.reserve(width: 1, height: 1))
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
