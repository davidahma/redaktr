import AppKit
import RedaktrCore
import XCTest

final class ScreenshotFolderWatchTests: XCTestCase {
    func testPlannerIgnoresSeededExistingFiles() {
        let existing = candidate(named: "existing.png", size: 100)
        var plan = ScreenshotFolderWatchPlan(settleInterval: 1)

        plan.seedKnownFiles([existing])
        plan.observe([existing], at: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(
            plan.readyCandidates(afterObserving: [existing], at: Date(timeIntervalSince1970: 12)),
            []
        )
    }

    func testPlannerWaitsUntilNewCandidateIsStable() {
        let first = candidate(named: "new.png", size: 100)
        let changed = candidate(named: "new.png", size: 140)
        var plan = ScreenshotFolderWatchPlan(settleInterval: 1)

        plan.observe([first], at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(
            plan.readyCandidates(afterObserving: [changed], at: Date(timeIntervalSince1970: 10.5)),
            []
        )
        XCTAssertEqual(
            plan.readyCandidates(afterObserving: [changed], at: Date(timeIntervalSince1970: 11.4)),
            []
        )

        XCTAssertEqual(
            plan.readyCandidates(afterObserving: [changed], at: Date(timeIntervalSince1970: 11.6)),
            [changed]
        )
        XCTAssertEqual(
            plan.readyCandidates(afterObserving: [changed], at: Date(timeIntervalSince1970: 12.8)),
            []
        )
    }

    func testSnapshotFiltersSupportedVisibleRegularImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("redaktr-watch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("screenshot.png")
        let unsupportedURL = directory.appendingPathComponent("notes.txt")
        let hiddenURL = directory.appendingPathComponent(".hidden.png")
        try makePNG(at: imageURL)
        try "not an image".write(to: unsupportedURL, atomically: true, encoding: .utf8)
        try makePNG(at: hiddenURL)

        let candidates = ScreenshotFolderWatchSnapshot.candidates(in: directory)

        XCTAssertEqual(candidates.map { $0.url.lastPathComponent }, ["screenshot.png"])
    }

    private func candidate(named name: String, size: Int64) -> ScreenshotWatchCandidate {
        ScreenshotWatchCandidate(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: size,
            modificationDate: Date(timeIntervalSince1970: Double(size))
        )
    }

    private func makePNG(at url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        try data.write(to: url, options: [.atomic])
    }
}
