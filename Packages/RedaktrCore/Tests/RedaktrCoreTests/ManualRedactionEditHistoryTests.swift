import CoreGraphics
import RedaktrCore
import XCTest

final class ManualRedactionEditHistoryTests: XCTestCase {
    func testUndoAndRedoManualCreation() throws {
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan.empty

        let previousPlan = plan
        let id = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        ))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))

        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertTrue(plan.manualDetections.isEmpty)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertEqual(plan.manualDetections.first?.id, id)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testUndoAndRedoManualDeletion() throws {
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan.empty
        let id = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        ))

        let previousPlan = plan
        XCTAssertTrue(plan.removeManualRedaction(id: id))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertEqual(plan.manualDetections.first?.id, id)

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertTrue(plan.manualDetections.isEmpty)
    }

    func testUndoAndRedoManualGeometryChange() throws {
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan.empty
        let id = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        ))

        let previousPlan = plan
        XCTAssertTrue(plan.updateManualRedaction(
            id: id,
            bounds: CGRect(x: 0.42, y: 0.50, width: 0.18, height: 0.16)
        ))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))

        XCTAssertTrue(history.undo(in: &plan))
        assertRect(
            try XCTUnwrap(plan.manualDetections.first?.normalizedBounds),
            equals: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        )

        XCTAssertTrue(history.redo(in: &plan))
        assertRect(
            try XCTUnwrap(plan.manualDetections.first?.normalizedBounds),
            equals: CGRect(x: 0.42, y: 0.50, width: 0.18, height: 0.16)
        )
    }

    func testUndoAndRedoAutomatedGeometryAdjustment() throws {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan(textDetections: [automatic])
        let previousPlan = plan

        XCTAssertTrue(plan.updateRedactionBounds(
            id: automatic.id,
            bounds: CGRect(x: 0.14, y: 0.66, width: 0.34, height: 0.12)
        ))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))
        XCTAssertEqual(plan.detections.first?.source, .user)
        XCTAssertEqual(plan.detections.first?.boundsPrecision, .manual)
        assertRect(
            try XCTUnwrap(plan.detections.first?.originalNormalizedBounds),
            equals: automatic.normalizedBounds
        )
        XCTAssertEqual(plan.detections.first?.originalSource, .deterministic)
        XCTAssertEqual(plan.detections.first?.originalBoundsPrecision, .tight)

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertEqual(plan.detections, [automatic])

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertEqual(plan.detections.first?.source, .user)
        XCTAssertEqual(plan.detections.first?.boundsPrecision, .manual)
        assertRect(
            try XCTUnwrap(plan.detections.first?.normalizedBounds),
            equals: CGRect(x: 0.14, y: 0.66, width: 0.34, height: 0.12)
        )
    }

    func testResetAutomatedGeometryAdjustmentRestoresOriginalDetectionMetadata() throws {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        var plan = RedactionPlan(textDetections: [automatic])

        XCTAssertTrue(plan.updateRedactionBounds(
            id: automatic.id,
            bounds: CGRect(x: 0.14, y: 0.66, width: 0.34, height: 0.12)
        ))
        XCTAssertTrue(plan.resetRedactionBounds(id: automatic.id))

        XCTAssertEqual(plan.detections, [automatic])
        XCTAssertFalse(plan.resetRedactionBounds(id: automatic.id))
    }

    func testUndoAndRedoLeavesAutomatedDetectionStateUnchanged() throws {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan(textDetections: [automatic])

        let previousPlan = plan
        _ = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        ))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))
        plan.setActive(false, for: automatic.id)

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertEqual(plan.detections, [automatic])
        XCTAssertFalse(try activeState(for: automatic.id, in: plan))

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertFalse(try activeState(for: automatic.id, in: plan))
        XCTAssertEqual(plan.entries.filter { $0.detection.source != .user }.map(\.detection), [automatic])
        XCTAssertEqual(plan.manualDetections.count, 1)
    }

    func testUndoAfterRescanKeepsUnrelatedAutomatedDetections() throws {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        let rescanned = Detection(
            kind: .ipAddress,
            label: "IP address",
            confidence: 0.86,
            normalizedBounds: CGRect(x: 0.52, y: 0.40, width: 0.20, height: 0.06),
            source: .deterministic,
            reason: "Detected IP address.",
            boundsPrecision: .tight
        )
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan(textDetections: [automatic])

        let previousPlan = plan
        _ = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.12)
        ))
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))

        plan = RedactionPlan(
            textDetections: [automatic, rescanned],
            manualDetections: plan.manualDetections
        )

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertEqual(plan.detections, [automatic, rescanned])

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertEqual(plan.entries.filter { $0.detection.source != .user }.map(\.detection), [automatic, rescanned])
        XCTAssertEqual(plan.manualDetections.count, 1)
    }

    func testUndoAndRedoKeepReadingOrder() throws {
        let top = Detection(
            kind: .email,
            label: "Top",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.80, width: 0.20, height: 0.05),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        let bottom = Detection(
            kind: .ipAddress,
            label: "Bottom",
            confidence: 0.86,
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.05),
            source: .deterministic,
            reason: "Detected IP address.",
            boundsPrecision: .tight
        )
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan(textDetections: [bottom, top])
        let previousPlan = plan

        _ = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: 0.10, y: 0.55, width: 0.20, height: 0.05),
            label: "Middle"
        ))
        XCTAssertEqual(plan.entries.map(\.detection.label), ["Top", "Middle", "Bottom"])
        XCTAssertTrue(history.recordChange(from: previousPlan, to: plan))

        XCTAssertTrue(history.undo(in: &plan))
        XCTAssertEqual(plan.entries.map(\.detection.label), ["Top", "Bottom"])

        XCTAssertTrue(history.redo(in: &plan))
        XCTAssertEqual(plan.entries.map(\.detection.label), ["Top", "Middle", "Bottom"])
    }

    func testRecordingIgnoresNonManualChanges() {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        var history = ManualRedactionEditHistory()
        var plan = RedactionPlan(textDetections: [automatic])
        let previousPlan = plan

        plan.setActive(false, for: automatic.id)

        XCTAssertFalse(history.recordChange(from: previousPlan, to: plan))
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.undo(in: &plan))
    }

    private func activeState(
        for id: Detection.ID,
        in plan: RedactionPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Bool {
        try XCTUnwrap(plan.entries.first { $0.id == id }, file: file, line: line).isActive
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
