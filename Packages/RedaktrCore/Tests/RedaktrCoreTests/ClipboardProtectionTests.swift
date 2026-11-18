import RedaktrCore
import XCTest

final class ClipboardProtectionTests: XCTestCase {
    func testConfigurationDefaultsToOptOutAndPauseIfUnsure() {
        let configuration = ClipboardProtectionConfiguration()

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.replacementMode, .pauseIfUnsure)
        XCTAssertEqual(configuration.replacementMode.safetyMode, .pauseIfUnsure)
    }

    func testLegacyReplacementModesNormalizeToAutoCleanSafetyModes() {
        XCTAssertEqual(ClipboardProtectionReplacementMode.askBeforeReplace.normalizedReplacementMode, .reviewFirst)
        XCTAssertEqual(ClipboardProtectionReplacementMode.autoReplace.normalizedReplacementMode, .pauseIfUnsure)
        XCTAssertEqual(ClipboardProtectionReplacementMode.autoCleanEverything.safetyMode, .autoCleanEverything)
        XCTAssertEqual(ClipboardProtectionReplacementMode.allCases, [.reviewFirst, .pauseIfUnsure, .autoCleanEverything])
    }

    func testMonitorPlanIgnoresNonImageClipboardChanges() {
        var plan = ClipboardProtectionMonitorPlan(settleInterval: 1)

        XCTAssertEqual(
            plan.observe(changeCount: 3, containsImage: false, at: Date(timeIntervalSince1970: 10)),
            .ignore
        )
        XCTAssertEqual(
            plan.observe(changeCount: 3, containsImage: true, at: Date(timeIntervalSince1970: 12)),
            .ignore
        )
    }

    func testMonitorPlanDebouncesImageClipboardChanges() {
        var plan = ClipboardProtectionMonitorPlan(settleInterval: 1)

        XCTAssertEqual(
            plan.observe(changeCount: 4, containsImage: true, at: Date(timeIntervalSince1970: 10)),
            .wait
        )
        XCTAssertEqual(
            plan.observe(changeCount: 4, containsImage: true, at: Date(timeIntervalSince1970: 10.5)),
            .wait
        )
        XCTAssertEqual(
            plan.observe(changeCount: 4, containsImage: true, at: Date(timeIntervalSince1970: 11.1)),
            .scan(changeCount: 4)
        )
        XCTAssertEqual(
            plan.observe(changeCount: 4, containsImage: true, at: Date(timeIntervalSince1970: 12.2)),
            .ignore
        )
    }

    func testMonitorPlanRestartsDebounceForNewImageChange() {
        var plan = ClipboardProtectionMonitorPlan(settleInterval: 1)

        XCTAssertEqual(
            plan.observe(changeCount: 4, containsImage: true, at: Date(timeIntervalSince1970: 10)),
            .wait
        )
        XCTAssertEqual(
            plan.observe(changeCount: 5, containsImage: true, at: Date(timeIntervalSince1970: 10.5)),
            .wait
        )
        XCTAssertEqual(
            plan.observe(changeCount: 5, containsImage: true, at: Date(timeIntervalSince1970: 11.4)),
            .wait
        )
        XCTAssertEqual(
            plan.observe(changeCount: 5, containsImage: true, at: Date(timeIntervalSince1970: 11.6)),
            .scan(changeCount: 5)
        )
    }

    func testMonitorPlanCanMarkReplacementChangeAsHandled() {
        var plan = ClipboardProtectionMonitorPlan(settleInterval: 0)

        plan.markHandled(changeCount: 8)

        XCTAssertEqual(
            plan.observe(changeCount: 8, containsImage: true, at: Date(timeIntervalSince1970: 10)),
            .ignore
        )
    }
}
