import AppKit
import ImageIO
import XCTest

@MainActor
final class RedaktrUITests: XCTestCase {
    private static let appID = "com.davidahma.redaktr.uitesting"
    private let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("redaktr-ui-\(UUID().uuidString)", isDirectory: true)
    private let pasteboardName = NSPasteboard.Name("com.davidahma.redaktr.uitesting.\(UUID().uuidString)")
    private var pasteboard: NSPasteboard { NSPasteboard(name: pasteboardName) }

    override func setUp() async throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let app = XCUIApplication(bundleIdentifier: Self.appID)
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
        }
        pasteboard.releaseGlobally()
        try FileManager.default.removeItem(at: fixtureRoot)
    }

    func testFreshLaunchShowsLocalOnlyFirstRunCopy() {
        let app = makeApp()
        app.launch()
        app.activate()

        assertMainTopControlsVisible(in: app)
        assertToolbarDropdownsOpen(in: app)
        XCTAssertTrue(button("open-image-button", in: app).isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["empty-getting-started-checklist"].exists)
        XCTAssertTrue(button("empty-open-image-button", in: app).exists)
        XCTAssertTrue(button("empty-paste-image-button", in: app).exists)
        XCTAssertTrue(button("empty-capture-area-button", in: app).exists)
        XCTAssertTrue(button("empty-open-batch-button", in: app).exists)
        XCTAssertFalse(button("clear-current-review-button", in: app).isEnabled)
        XCTAssertFalse(button("previous-finding-button", in: app).exists)
        XCTAssertFalse(button("toggle-selected-finding-button", in: app).exists)
        XCTAssertFalse(app.checkBoxes["manual-draw-toggle"].exists)
        XCTAssertTrue(app.staticTexts["local-only-copy-text"].exists)
        XCTAssertFalse(button("export-redacted-button", in: app).isEnabled)

        let openAction = button("empty-open-image-button", in: app)
        let pasteAction = button("empty-paste-image-button", in: app)
        let captureAction = button("empty-capture-area-button", in: app)
        let batchAction = button("empty-open-batch-button", in: app)
        XCTAssertGreaterThanOrEqual(openAction.frame.width, pasteAction.frame.width)
        for action in [openAction, pasteAction, captureAction, batchAction] {
            XCTAssertGreaterThanOrEqual(action.frame.height, 32)
            XCTAssertLessThanOrEqual(abs(action.frame.height - openAction.frame.height), 2)
        }
    }

    func testDarkModeSmokeCoversCoreScreens() throws {
        let emptyApp = makeApp()
        emptyApp.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        emptyApp.launch()
        emptyApp.activate()

        XCTAssertTrue(button("empty-open-image-button", in: emptyApp).waitForExistence(timeout: 5))
        XCTAssertTrue(button("empty-paste-image-button", in: emptyApp).exists)
        XCTAssertTrue(button("empty-capture-area-button", in: emptyApp).exists)
        emptyApp.terminate()
        _ = emptyApp.wait(for: .notRunning, timeout: 5)

        let context = try launchWithFixture(
            launchArguments: ["-AppleInterfaceStyle", "Dark"]
        )
        let app = context.app

        XCTAssertTrue(app.staticTexts["redaction-count-label"].exists)
        XCTAssertTrue(button("copy-redacted-button", in: app).isEnabled)
        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["findings-filter-picker"].exists)

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["Detection"].exists)
        clickSettingsTab("Protection", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-summary"].exists)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testFirstLaunchQuickStartCanLoadSample() {
        let app = makeApp()
        app.launchEnvironment["REDAKTR_UI_FORCE_ONBOARDING"] = "1"
        app.launchEnvironment["REDAKTR_UI_SUPPRESS_AUTO_RESCAN"] = "1"
        app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = "Contact maya@example.com before sharing"
        app.launchArguments += ["-redaktrDidCompleteOnboardingV1", "NO"]
        app.launch()
        app.activate()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-quick-start-title"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-step-start"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-step-review"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-step-export"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-step-capture-shortcuts"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-step-detection-tuning"].exists)
        XCTAssertTrue(button("onboarding-try-sample-button", in: app).exists)
        XCTAssertTrue(button("onboarding-finish-button", in: app).exists || app.buttons["Start Using Redaktr"].exists)

        button("onboarding-try-sample-button", in: app).click()
        let sampleStatus = button("ui-test-sample-status", in: app)
        XCTAssertTrue(sampleStatus.waitForExistence(timeout: 5))
        let sampleLoadedPredicate = NSPredicate(format: "label == %@", "loaded 1")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: sampleLoadedPredicate, object: sampleStatus)], timeout: 5),
            .completed,
            "Expected sample loader to report one fixture finding, got '\(sampleStatus.label)'."
        )
        XCTAssertTrue(app.staticTexts["redaction-count-label"].waitForExistence(timeout: 10))
        XCTAssertRedactionCount("1 of 1 will redact", in: app, timeout: 10)
    }

    func testInstallReminderAppearsForDownloadedCopy() {
        let app = makeApp()
        app.launchEnvironment["REDAKTR_UI_INSTALL_LOCATION_OVERRIDE"] = "/Users/tester/Downloads/Redaktr.app"
        app.launch()
        app.activate()

        XCTAssertTrue(installReminderExists(in: app, timeout: 5))
        XCTAssertTrue(
            button("install-reminder-open-applications-button", in: app).exists
                || app.buttons["Open Applications Folder"].exists
        )
        XCTAssertTrue(button("install-reminder-not-now-button", in: app).exists || app.buttons["Not Now"].exists)
        XCTAssertTrue(
            button("install-reminder-dismiss-permanently-button", in: app).exists
                || app.buttons["Don't Ask Again"].exists
        )

        let notNow = button("install-reminder-not-now-button", in: app)
        if notNow.exists {
            notNow.click()
        } else {
            app.buttons["Not Now"].click()
        }
        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 3))
    }

    func testInstallReminderDoesNotAppearForApplicationsCopy() {
        let app = makeApp()
        app.launchEnvironment["REDAKTR_UI_INSTALL_LOCATION_OVERRIDE"] = "/Applications/Redaktr.app"
        app.launch()
        app.activate()

        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(installReminderExists(in: app, timeout: 0.5))
    }

    func testInstallReminderDoesNotAppearForDataVolumeApplicationsCopy() {
        let app = makeApp()
        app.launchEnvironment["REDAKTR_UI_INSTALL_LOCATION_OVERRIDE"] = "/System/Volumes/Data/Applications/Redaktr.app"
        app.launch()
        app.activate()

        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(installReminderExists(in: app, timeout: 0.5))
    }

    func testLaunchWithFixtureReachesReviewScreenAndExportState() throws {
        let context = try launchWithFixture()
        let app = context.app

        XCTAssertTrue(app.staticTexts["redaction-count-label"].waitForExistence(timeout: 5))
        XCTAssertEqual(button("redaction-count-value", in: app).label, "1 of 1 will redact")
        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)
        XCTAssertTrue(button("copy-redacted-button", in: app).isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["preview-redacted-output-toggle"].exists)
        XCTAssertTrue(button("next-finding-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["findings-filter-picker"].exists)
        XCTAssertTrue(button("toggle-selected-finding-button", in: app).isEnabled)
        XCTAssertTrue(button("reset-selected-bounds-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["policy-action-reason-11111111-2222-3333-4444-555555555555"].exists)
        let previewToggle = app.descendants(matching: .any)["preview-redacted-output-toggle"].firstMatch
        XCTAssertTrue(previewToggle.waitForExistence(timeout: 2))
        chooseReviewCommand("Preview Cleaned Output", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["preview-output-banner"].waitForExistence(timeout: 2))

        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)
        XCTAssertTrue(button("clear-current-review-button", in: app).isEnabled)
        button("clear-current-review-button", in: app).click()

        XCTAssertTrue(button("empty-open-image-button", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(button("export-redacted-button", in: app).isEnabled)
    }

    func testFailedScanBlocksSharingUntilManualReview() throws {
        let app = try launchWithFixture(failScan: true).app
        let confirm = button("confirm-manual-review-button", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(button("copy-redacted-button", in: app).isEnabled)
        XCTAssertFalse(button("export-redacted-button", in: app).isEnabled)

        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertNil(pasteboard.data(forType: .png))

        confirm.click()
        XCTAssertTrue(button("copy-redacted-button", in: app).isEnabled)
        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)
    }

    func testFailedBatchItemBlocksBulkExportUntilManualReview() throws {
        let app = try launchWithBatchFixtures(failSecondScan: true).app
        clickControl("batch-filter-all", in: app)
        let failed = app.descendants(matching: .any)["batch-row-redaktr-ui-batch-2.png"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        failed.click()
        let confirm = button("confirm-manual-review-button", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let bulkExport = button("export-batch-button", in: app)
        XCTAssertFalse(bulkExport.isEnabled)
        confirm.click()
        XCTAssertTrue(bulkExport.isEnabled)
    }

    func testLaunchWithBatchFixturesShowsQueueAndBulkExportState() throws {
        let context = try launchWithBatchFixtures()
        let app = context.app

        XCTAssertTrue(app.descendants(matching: .any)["batch-queue-sidebar"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["2 of 2 scanned - 2 with findings - 0 clean"].exists)
        XCTAssertTrue(app.staticTexts["Reviewed 1 of 2 with findings"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["All images"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Findings"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Clean"].exists)
        XCTAssertTrue(button("export-batch-button", in: app).isEnabled)
        XCTAssertTrue(app.checkBoxes["include-clean-batch-items-toggle"].exists)
        XCTAssertEqual(button("redaction-count-value", in: app).label, "1 of 1 will redact")
        XCTAssertTrue(button("clear-current-review-button", in: app).isEnabled)

        button("clear-current-review-button", in: app).click()

        XCTAssertTrue(button("empty-open-image-button", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["batch-queue-sidebar"].exists)
    }

    func testBatchFilterAndArrowNavigationMoveThroughReviewImages() throws {
        let context = try launchWithBatchFixtures(seedDetectionsFirstItemOnly: true)
        let app = context.app
        let firstBatchItem = app.descendants(matching: .any)["batch-row-redaktr-ui-batch-1.png"]
        let secondBatchItem = app.descendants(matching: .any)["batch-row-redaktr-ui-batch-2.png"]

        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reviewed 1 of 1 with findings"].waitForExistence(timeout: 2))
        XCTAssertFalse(secondBatchItem.exists)
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        clickControl("batch-filter-all", in: app)
        XCTAssertTrue(secondBatchItem.waitForExistence(timeout: 2))
        firstBatchItem.click()

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertRedactionCount("0 of 0 will redact", in: app)

        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        clickControl("batch-filter-clean", in: app)
        XCTAssertTrue(secondBatchItem.waitForExistence(timeout: 2))
        XCTAssertRedactionCount("0 of 0 will redact", in: app)

        clickControl("batch-filter-findings", in: app)
        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 2))
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testBatchCategoryFilterNarrowsQueueAndCanClear() throws {
        let context = try launchWithBatchFixtures(seedMixedBatchCategories: true)
        let app = context.app
        let firstBatchItem = app.descendants(matching: .any)["batch-row-redaktr-ui-batch-1.png"]
        let secondBatchItem = app.descendants(matching: .any)["batch-row-redaktr-ui-batch-2.png"]

        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 5))
        XCTAssertTrue(secondBatchItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 of 2 scanned - 2 with findings - 0 clean"].waitForExistence(timeout: 5))
        XCTAssertTrue(button("batch-category-filter-emails", in: app).waitForExistence(timeout: 5))

        clickControl("batch-category-filter-emails", in: app)
        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 2))
        XCTAssertFalse(secondBatchItem.exists)
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 2))

        clickControl("batch-category-filter-customerAccount", in: app)
        XCTAssertTrue(secondBatchItem.waitForExistence(timeout: 2))
        XCTAssertFalse(firstBatchItem.exists)

        clickControl("batch-category-filter-all", in: app)
        XCTAssertTrue(firstBatchItem.waitForExistence(timeout: 2))
        XCTAssertTrue(secondBatchItem.waitForExistence(timeout: 2))

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testDetectionToggleUpdatesIncludedCountWithoutBlockingExport() throws {
        let context = try launchWithFixture()
        let app = context.app
        let checkbox = app.descendants(matching: .any)["detection-toggle-11111111-2222-3333-4444-555555555555"]

        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.click()
        XCTAssertEqual(button("redaction-count-value", in: app).label, "0 of 1 will redact")
        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)

        checkbox.click()
        XCTAssertEqual(button("redaction-count-value", in: app).label, "1 of 1 will redact")
        XCTAssertTrue(button("export-redacted-button", in: app).isEnabled)
    }

    func testReviewKeyboardShortcutsDrivePrimaryActions() throws {
        let context = try launchWithFixture(exportToAppTemp: true)
        let app = context.app

        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["preview-output-banner"].waitForExistence(timeout: 3))

        app.typeKey(.space, modifierFlags: [])
        XCTAssertRedactionCount("0 of 1 will redact", in: app)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        pasteboard.clearContents()
        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Copied cleaned PNG"].waitForExistence(timeout: 3))
        XCTAssertNotNil(pasteboard.data(forType: .png))

        app.typeKey("e", modifierFlags: .command)
        XCTAssertCompletionBanner("Exported cleaned PNG", in: app, timeout: 3)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(button("empty-open-image-button", in: app).waitForExistence(timeout: 3))

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testPasteImageKeyboardShortcutLoadsClipboardImage() throws {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-paste-shortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-paste-fixture.png")
        try makeFixturePNG(at: fixtureURL)

        guard let fixtureImage = NSImage(contentsOf: fixtureURL) else {
            XCTFail("Could not read paste shortcut fixture image.")
            return
        }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fixtureImage]))

        let app = makeApp()
        app.launch()
        app.activate()

        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
        app.typeKey("v", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.staticTexts["Clipboard image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["redaction-count-label"].waitForExistence(timeout: 10))

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testFindingNavigationAndRescanKeyboardShortcutsAreWired() throws {
        let context = try launchWithFixture(
            seedReviewDetection: true,
            uiTextObservation: "Contact sam@example.com before sharing"
        )
        let app = context.app

        XCTAssertRedactionCount("2 of 2 will redact", in: app)
        XCTAssertPolicyActionReason(
            "policy-action-reason-11111111-2222-3333-4444-555555555555",
            contains: "Auto-redacted",
            in: app
        )

        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertPolicyActionReason(
            "policy-action-reason-22222222-3333-4444-5555-666666666666",
            contains: "Needs review",
            in: app
        )

        app.typeKey(.upArrow, modifierFlags: .command)
        XCTAssertPolicyActionReason(
            "policy-action-reason-11111111-2222-3333-4444-555555555555",
            contains: "Auto-redacted",
            in: app
        )

        app.typeKey("d", modifierFlags: .command)
        XCTAssertRedactionCount("1 of 1 will redact", in: app, timeout: 10)
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["UI fixture review item"].waitForExistence(timeout: 1))

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testFindingBulkActionsAndFiltersUpdateCounts() throws {
        let context = try launchWithFixture(seedReviewDetection: true)
        let app = context.app

        XCTAssertRedactionCount("2 of 2 will redact", in: app)
        chooseReviewCommand("Make All Findings Visible", in: app)
        XCTAssertRedactionCount("0 of 2 will redact", in: app)

        clickControl("findings-filter-off", in: app)
        XCTAssertTrue(app.staticTexts["UI fixture email"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["UI fixture review item"].exists)

        clickControl("findings-filter-included", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["empty-filter-state"].waitForExistence(timeout: 2))

        chooseReviewCommand("Redact All Findings", in: app)
        XCTAssertRedactionCount("2 of 2 will redact", in: app)

        clickControl("findings-filter-needsReview", in: app)
        XCTAssertTrue(app.staticTexts["UI fixture review item"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["UI fixture email"].exists)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testCopyWritesCleanedPNGToPasteboardAndShowsCompletion() throws {
        let context = try launchWithFixture()
        let app = context.app

        pasteboard.clearContents()
        button("copy-redacted-button", in: app).click()

        XCTAssertTrue(app.descendants(matching: .any)["completion-banner"].waitForExistence(timeout: 3))
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 480)
        XCTAssertEqual(image.height, 300)
        XCTAssertEqual(try rgbaPixel(in: image, x: 170, y: 100), [0, 0, 0, 255])
        XCTAssertEqual(try rgbaPixel(in: image, x: 20, y: 20), [255, 255, 255, 255])

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testWatchedScreenshotFindingQueuesAlertWithoutReplacingCurrentReview() throws {
        let context = try launchWithFixture(seedWatchedScreenshot: true)
        let app = context.app

        XCTAssertTrue(app.staticTexts["UI fixture email"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Watched fixture email"].exists)

        let watchedAlertsMenu = app.descendants(matching: .any)["watched-alerts-menu"].firstMatch
        XCTAssertTrue(watchedAlertsMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["UI fixture email"].exists)
        XCTAssertFalse(app.alerts["Possible leaks found"].exists)
        watchedAlertsMenu.click()
        let queuedItem = app.menuItems["redaktr-ui-watched-fixture.png - 1 finding"].firstMatch
        XCTAssertTrue(queuedItem.waitForExistence(timeout: 3))
        queuedItem.click()
        XCTAssertTrue(app.staticTexts["Watched fixture email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["UI fixture email"].exists)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testReviewWarningPrecedesCopyWhenFindingsNeedCheck() throws {
        let context = try launchWithFixture(seedReviewDetection: true)
        let app = context.app

        pasteboard.clearContents()
        button("copy-redacted-button", in: app).click()

        let copyAnyway = app.sheets.buttons["Copy anyway"].firstMatch
        XCTAssertTrue(copyAnyway.waitForExistence(timeout: 3))
        XCTAssertNil(pasteboard.data(forType: .png))

        copyAnyway.click()
        XCTAssertTrue(app.descendants(matching: .any)["completion-banner"].waitForExistence(timeout: 3))
        XCTAssertNotNil(pasteboard.data(forType: .png))

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testDirectExportWritesCleanedImageAndRecordsHistory() throws {
        let context = try launchWithFixture(exportToAppTemp: true, resetHistory: true)
        let app = context.app

        chooseReviewCommand("Export Cleaned Copy", in: app)

        XCTAssertTrue(app.descendants(matching: .any)["completion-banner"].waitForExistence(timeout: 3))

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        clickSettingsTab("Privacy", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["safe-share-history-list"].waitForExistence(timeout: 2))

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testManualRedactionControlIsReachable() throws {
        let context = try launchWithFixture()
        let app = context.app
        let manualToggle = app.checkBoxes["manual-draw-toggle"]

        XCTAssertTrue(manualToggle.waitForExistence(timeout: 5))
        manualToggle.click()
        XCTAssertTrue(manualToggle.exists)
    }

    func testManualRedactionDeleteUndoAndRedoAreWired() throws {
        let context = try launchWithFixture(seedManualDetection: true)
        let app = context.app

        XCTAssertRedactionCount("2 of 2 will redact", in: app)
        let manualRow = app.staticTexts["Manual redaction"].firstMatch
        XCTAssertTrue(manualRow.waitForExistence(timeout: 3))
        clickElement(manualRow)
        XCTAssertTrue(button("delete-selected-manual-redaction-button", in: app).isEnabled)

        chooseReviewCommand("Delete Selected Manual Redaction", in: app)
        XCTAssertRedactionCount("1 of 1 will redact", in: app)
        XCTAssertTrue(button("undo-manual-edit-button", in: app).isEnabled)

        chooseReviewCommand("Undo Manual Edit", in: app)
        XCTAssertRedactionCount("2 of 2 will redact", in: app)
        XCTAssertTrue(button("redo-manual-edit-button", in: app).isEnabled)

        chooseReviewCommand("Redo Manual Edit", in: app)
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testManualRedactionUndoRedoKeyboardShortcutsAreWired() throws {
        let context = try launchWithFixture(seedManualDetection: true)
        let app = context.app

        XCTAssertRedactionCount("2 of 2 will redact", in: app)
        let manualRow = app.staticTexts["Manual redaction"].firstMatch
        XCTAssertTrue(manualRow.waitForExistence(timeout: 3))
        clickElement(manualRow)

        chooseReviewCommand("Delete Selected Manual Redaction", in: app)
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        chooseReviewCommand("Undo Manual Edit", in: app)
        XCTAssertRedactionCount("2 of 2 will redact", in: app)

        chooseReviewCommand("Redo Manual Edit", in: app)
        XCTAssertRedactionCount("1 of 1 will redact", in: app)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testDirectBatchExportHonorsIncludeSafeToggle() throws {
        let context = try launchWithBatchFixtures(
            seedDetectionsFirstItemOnly: true,
            batchExportToAppTemp: true,
            resetHistory: true
        )
        let app = context.app

        app.checkBoxes["include-clean-batch-items-toggle"].click()
        button("export-batch-button", in: app).click()

        XCTAssertCompletionBanner("Exported 1 cleaned copies", in: app, timeout: 3)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testSettingsExposeCustomDetectionControls() {
        let app = makeApp()
        app.launch()
        app.activate()

        openSettings(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["Detection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.radioButtons["Protection"].exists)
        XCTAssertTrue(app.radioButtons["Privacy"].exists)
        XCTAssertTrue(app.radioButtons["Help"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["policy-preset-picker"].exists)
        XCTAssertTrue(button("settings-help-policy-preset", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["policy-claim-boundary-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["policy-pack-summary-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["custom-terms-editor"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["custom-regexes-editor"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["allowlist-editor"].exists)

        for categoryID in [
            "emails",
            "phones",
            "cards",
            "ipAddresses",
            "secrets",
            "highEntropy",
            "visualCodes",
            "faces",
            "customerAccount",
            "custom"
        ] {
            let row = app.descendants(matching: .any)["detector-category-row-\(categoryID)"].firstMatch
            XCTAssertTrue(
                scrollToElement(row, in: app),
                "Missing detector category row \(categoryID)."
            )
        }
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["advanced-detector-details"].firstMatch, in: app))

        clickSettingsTab("Protection", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screenshot-protection-status-section"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["screenshot-protection-ai-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["protection-status-redaktrCapture"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["protection-status-folderWatch"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["protection-status-clipboardGuard"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["protection-status-policy"].exists)
        XCTAssertTrue(button("protection-status-action-redaktrCapture", in: app).exists)
        XCTAssertTrue(button("protection-status-action-folderWatch", in: app).exists)
        XCTAssertTrue(button("protection-status-action-clipboardGuard", in: app).exists)
        XCTAssertTrue(button("protection-status-action-policy", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["screenshot-watch-enable-toggle"].exists)
        XCTAssertTrue(button("settings-help-screenshot-folder-watch", in: app).exists)
        XCTAssertTrue(button("screenshot-watch-choose-folder-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["screenshot-watch-boundary-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clipboard-protection-enable-toggle"].exists)
        XCTAssertTrue(button("settings-help-clipboard-protection", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["clipboard-protection-mode-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["clipboard-protection-boundary-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-output-mode-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-output-safety-mode-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-output-summary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-output-temporary-copy"].exists)
        XCTAssertTrue(button("capture-output-choose-folder-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-picker-area"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-picker-window"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-picker-screen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-defaults-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-shortcut-summary"].exists)

        clickSettingsTab("Privacy", in: app)
        XCTAssertTrue(button("export-custom-settings-button", in: app).exists)
        XCTAssertTrue(button("import-custom-settings-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-portability-boundary-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["safe-share-history-boundary-copy"].exists)
        XCTAssertTrue(button("clear-safe-share-history-button", in: app).exists)

        clickSettingsTab("Help", in: app)
        XCTAssertTrue(button("open-help-center-button", in: app).exists)
        XCTAssertTrue(button("quick-start-settings-button", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-help-summary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-contact-summary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-contact-repository-link"].exists)
    }

    func testScreenshotWatchShowsNotificationRecoveryWhenAlreadyEnabledAndNotificationsDenied() {
        let app = makeApp(
            screenshotWatchEnabled: "YES",
            screenshotWatchFolderPath: fixtureRoot.path,
            screenshotWatchFolderDisplayName: "Temporary Items"
        )
        app.launchEnvironment["REDAKTR_UI_NOTIFICATION_AUTHORIZATION_STATUS"] = "denied"
        app.launch()
        app.activate()

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))

        clickSettingsTab("Protection", in: app)
        let status = app.descendants(matching: .any)["screenshot-watch-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibleText(for: status).localizedCaseInsensitiveContains("notifications are off"))
        XCTAssertTrue(button("screenshot-watch-open-notification-settings-button", in: app).exists)
    }

    func testCaptureShortcutConflictStateIsVisibleInSettings() {
        let app = makeApp(
            areaShortcutID: "optionShift1",
            windowShortcutID: "optionShift1",
            screenShortcutID: "optionShift3"
        )
        app.launch()
        app.activate()

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))

        clickSettingsTab("Protection", in: app)
        let summary = app.descendants(matching: .any)["capture-shortcut-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibleText(for: summary).localizedCaseInsensitiveContains("duplicate shortcut"))
    }

    func testDefaultCaptureHotkeysLoadCaptureFixtureForAllModes() throws {
        let modes: [(key: String, sourceLabel: String)] = [
            ("1", "Area capture"),
            ("2", "Window capture"),
            ("3", "Screen capture")
        ]

        for mode in modes {
            let tempDirectory = fixtureRoot
                .appendingPathComponent("redaktr-ui-capture-shortcut-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-capture-fixture.png")
            try makeFixturePNG(at: fixtureURL)

            let app = makeApp()
            app.launchEnvironment["REDAKTR_UI_CAPTURE_FIXTURE_PATH"] = fixtureURL.path
            app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = "Project release notes"
            app.launchEnvironment["REDAKTR_UI_ENABLE_GLOBAL_CAPTURE_SHORTCUTS"] = "1"
            app.launch()
            app.activate()

            XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
            app.typeKey(mode.key, modifierFlags: [.option, .shift])

            XCTAssertTrue(
                app.staticTexts[mode.sourceLabel].waitForExistence(timeout: 10),
                "Expected \(mode.sourceLabel) after pressing Option-Shift-\(mode.key)."
            )
            XCTAssertTrue(app.staticTexts["redaction-count-label"].waitForExistence(timeout: 10))

            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCaptureHotkeyAutoCopyModeCopiesCleanedPNGWithoutOpeningReview() throws {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-capture-auto-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-capture-auto-copy-fixture.png")
        try makeFixturePNG(at: fixtureURL)

        pasteboard.clearContents()
        let app = makeApp(captureOutputModeID: "copyCleanedPNG")
        app.launchEnvironment["REDAKTR_UI_CAPTURE_FIXTURE_PATH"] = fixtureURL.path
        app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = "Project release notes"
        app.launchEnvironment["REDAKTR_UI_ENABLE_GLOBAL_CAPTURE_SHORTCUTS"] = "1"
        app.launch()
        app.activate()

        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: [.option, .shift])

        let copied = waitUntil(timeout: 10) {
            pasteboard.data(forType: .png) != nil
        }
        XCTAssertTrue(copied, "Expected auto-copy capture mode to write a cleaned PNG to the pasteboard.")
        XCTAssertFalse(app.staticTexts["Area capture"].waitForExistence(timeout: 1))
        XCTAssertTrue(button("open-image-button", in: app).exists)
        let completionBanner = app.descendants(matching: .any)["completion-banner"].firstMatch
        XCTAssertTrue(completionBanner.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibleText(for: completionBanner).localizedCaseInsensitiveContains("cleaned screenshot copied"))
        XCTAssertTrue(app.descendants(matching: .any)["completion-banner-action-button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["completion-banner-secondary-action-button"].exists)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCustomCaptureHotkeyChoiceLoadsCaptureFixture() throws {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-custom-capture-shortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-custom-capture-fixture.png")
        try makeFixturePNG(at: fixtureURL)

        let app = makeApp(areaShortcutID: "controlOption1")
        app.launchEnvironment["REDAKTR_UI_CAPTURE_FIXTURE_PATH"] = fixtureURL.path
        app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = "Project release notes"
        app.launchEnvironment["REDAKTR_UI_ENABLE_GLOBAL_CAPTURE_SHORTCUTS"] = "1"
        app.launch()
        app.activate()

        XCTAssertTrue(button("open-image-button", in: app).waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: [.control, .option])

        XCTAssertTrue(
            app.staticTexts["Area capture"].waitForExistence(timeout: 10),
            "Expected custom Control-Option-1 area capture shortcut to load the capture fixture."
        )
        XCTAssertTrue(app.staticTexts["redaction-count-label"].waitForExistence(timeout: 10))

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testSettingsTabsStayReachableAfterScrolling() {
        let app = makeApp()
        app.launch()
        app.activate()

        openSettings(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["Detection"].waitForExistence(timeout: 3))

        app.typeKey(.pageDown, modifierFlags: [])
        app.typeKey(.pageDown, modifierFlags: [])

        XCTAssertTrue(app.radioButtons["Help"].isHittable)
        clickSettingsTab("Help", in: app)
        XCTAssertTrue(button("open-help-center-button", in: app).exists)

        XCTAssertTrue(app.radioButtons["Detection"].isHittable)
        clickSettingsTab("Detection", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["policy-preset-picker"].exists)
    }

    func testDetectionSettingsEditorRescansCurrentImageForCustomTerm() throws {
        let context = try launchWithDetectionSettingsFixture(
            customTerms: nil,
            customRegexes: nil,
            allowlist: nil,
            resetDetectionSettings: true
        )
        let app = context.app

        XCTAssertRedactionCount("0 of 0 will redact", in: app)
        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))

        let termsEditor = settingsEditor("custom-terms-editor-input", in: app)
        XCTAssertTrue(termsEditor.waitForExistence(timeout: 3))
        termsEditor.click()
        termsEditor.typeText(Self.customTermFixtureText)

        XCTAssertRedactionCount("1 of 1 will redact", in: app, timeout: 10)
        XCTAssertTrue(app.staticTexts["Custom term"].waitForExistence(timeout: 3))

        termsEditor.click()
        termsEditor.typeKey("a", modifierFlags: .command)
        termsEditor.typeKey(.delete, modifierFlags: [])
        XCTAssertRedactionCount("0 of 0 will redact", in: app, timeout: 10)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testStoredDetectionSettingsFeedRegexAndAllowlistIntoDetector() throws {
        let regexContext = try launchWithDetectionSettingsFixture(customRegexes: #"TICKET-[0-9]+"#)
        let regexApp = regexContext.app

        XCTAssertRedactionCount("1 of 1 will redact", in: regexApp, timeout: 10)
        XCTAssertTrue(regexApp.staticTexts["Custom pattern"].waitForExistence(timeout: 3))
        regexApp.terminate()
        _ = regexApp.wait(for: .notRunning, timeout: 5)
        try? FileManager.default.removeItem(at: regexContext.tempDirectory)

        let allowlistContext = try launchWithDetectionSettingsFixture(
            customTerms: Self.customTermFixtureText,
            allowlist: Self.customTermFixtureText
        )
        let allowlistApp = allowlistContext.app

        XCTAssertRedactionCount("0 of 0 will redact", in: allowlistApp, timeout: 10)
        XCTAssertFalse(allowlistApp.staticTexts["Custom term"].waitForExistence(timeout: 1))
        try? FileManager.default.removeItem(at: allowlistContext.tempDirectory)
    }

    func testDetectorCategoryDispositionOffRescansAndSuppressesEmail() throws {
        let context = try launchWithDetectionSettingsFixture(
            customTerms: nil,
            customRegexes: nil,
            allowlist: nil,
            resetDetectionSettings: true,
            uiTextObservation: "Contact sam@example.com before sharing"
        )
        let app = context.app

        XCTAssertRedactionCount("1 of 1 will redact", in: app, timeout: 10)
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 3))

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        let emailRow = app.descendants(matching: .any)["detector-category-row-emails"].firstMatch
        XCTAssertTrue(scrollToElement(emailRow, in: app))
        clickControl("Off", in: emailRow, file: #filePath, line: #line)
        app.typeKey("w", modifierFlags: .command)

        XCTAssertRedactionCount("0 of 0 will redact", in: app, timeout: 10)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testRememberSafeActionAddsAllowlistAndSuppressesRescan() throws {
        let context = try launchWithDetectionSettingsFixture(
            customTerms: nil,
            customRegexes: nil,
            allowlist: nil,
            resetDetectionSettings: true,
            uiTextObservation: "Contact sam@example.com before sharing"
        )
        let app = context.app

        XCTAssertRedactionCount("1 of 1 will redact", in: app, timeout: 10)
        app.staticTexts["Email"].firstMatch.click()
        let rememberSafeButton = button("remember-safe-finding-button", in: app)
        XCTAssertTrue(rememberSafeButton.waitForExistence(timeout: 3))
        rememberSafeButton.click()

        XCTAssertRedactionCount("0 of 0 will redact", in: app, timeout: 10)

        try? FileManager.default.removeItem(at: context.tempDirectory)
    }

    func testHelpCenterAndQuickStartReferenceAreReachable() {
        let app = makeApp()
        app.launch()
        app.activate()

        let helpMenu = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 5))
        helpMenu.click()
        XCTAssertTrue(app.menuItems["Show Quick Start"].waitForExistence(timeout: 5))
        app.menuItems["Show Quick Start"].click()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-quick-start-title"].exists)
        app.terminate()

        let helpApp = makeApp()
        helpApp.launch()
        helpApp.activate()

        let helpCenterMenu = helpApp.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpCenterMenu.waitForExistence(timeout: 5))
        helpCenterMenu.click()
        XCTAssertTrue(helpApp.menuItems["Redaktr Help Center"].waitForExistence(timeout: 5))
        helpApp.menuItems["Redaktr Help Center"].click()

        XCTAssertTrue(helpApp.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(helpApp.staticTexts["Getting Started"].waitForExistence(timeout: 2))

        clickControl("Shortcuts", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-shortcuts-section"].waitForExistence(timeout: 2))
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-shortcut-row-open"].exists)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-shortcut-row-capture-area"].exists)

        clickControl("Finding States", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-finding-states-section"].waitForExistence(timeout: 2))
        XCTAssertTrue(helpApp.descendants(matching: .any)["finding-state-legend-check"].exists)
        XCTAssertTrue(helpApp.descendants(matching: .any)["finding-state-legend-redact"].exists)
        XCTAssertTrue(helpApp.descendants(matching: .any)["finding-state-legend-visible"].exists)

        clickControl("Detection", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-detection-section"].waitForExistence(timeout: 2))

        clickControl("Protection Modes", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-protection-modes-section"].waitForExistence(timeout: 2))

        clickControl("Privacy", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-privacy-section"].waitForExistence(timeout: 2))

        clickControl("Contact", in: helpApp)
        XCTAssertTrue(helpApp.descendants(matching: .any)["help-contact-section"].waitForExistence(timeout: 2))
        let closeButton = helpApp.buttons["Close Help Center"].firstMatch
        if closeButton.waitForExistence(timeout: 1) {
            closeButton.click()
        } else if helpApp.buttons["Done"].firstMatch.waitForExistence(timeout: 1) {
            helpApp.buttons["Done"].firstMatch.click()
        } else {
            helpApp.typeKey("w", modifierFlags: .command)
        }
        XCTAssertFalse(helpApp.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 1))
    }

    func testHelpCenterActionButtonsOpenQuickStartAndSettings() {
        let app = makeApp()
        app.launch()
        app.activate()

        let helpCenterMenu = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpCenterMenu.waitForExistence(timeout: 5))
        helpCenterMenu.click()
        XCTAssertTrue(app.menuItems["Redaktr Help Center"].waitForExistence(timeout: 5))
        app.menuItems["Redaktr Help Center"].click()

        XCTAssertTrue(app.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 5))
        let quickStartButton = app.buttons["Quick Start"].firstMatch
        XCTAssertTrue(quickStartButton.waitForExistence(timeout: 3))
        quickStartButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-quick-start-title"].exists)

        let onboardingHelpButton = app.descendants(matching: .any)["onboarding-help-button"].firstMatch
        XCTAssertTrue(onboardingHelpButton.waitForExistence(timeout: 3))
        onboardingHelpButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 5))

        let settingsButton = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 1))
    }

    func testGettingStartedChecklistIsReachableAndNonBlocking() {
        let app = makeApp()
        app.launch()
        app.activate()

        XCTAssertTrue(button("empty-open-image-button", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(button("empty-paste-image-button", in: app).exists)
        XCTAssertTrue(button("empty-capture-area-button", in: app).exists)
        XCTAssertTrue(button("empty-open-batch-button", in: app).exists)

        XCTAssertTrue(app.descendants(matching: .any)["empty-getting-started-checklist"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-open-or-paste"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-review-finding"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-export-copy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-capture-shortcuts"].exists)

        button("getting-started-dismiss-button", in: app).click()
        XCTAssertFalse(app.descendants(matching: .any)["empty-getting-started-checklist"].waitForExistence(timeout: 1))

        let helpMenu = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 5))
        helpMenu.click()
        XCTAssertTrue(app.menuItems["Redaktr Help Center"].waitForExistence(timeout: 5))
        app.menuItems["Redaktr Help Center"].click()

        XCTAssertTrue(app.descendants(matching: .any)["help-center-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Getting Started"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-custom-term"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["getting-started-protection-modes"].exists)
    }

    private func launchWithFixture(
        failScan: Bool = false,
        seedManualDetection: Bool = false,
        seedReviewDetection: Bool = false,
        exportURL: URL? = nil,
        exportToAppTemp: Bool = false,
        resetHistory: Bool = false,
        uiTextObservation: String? = nil,
        seedWatchedScreenshot: Bool = false,
        launchArguments: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FixtureContext {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-fixture.png")
        try makeFixturePNG(at: fixtureURL)

        let app = makeApp()
        app.launchArguments += launchArguments
        app.launchEnvironment["REDAKTR_UI_FIXTURE_PATH"] = fixtureURL.path
        if failScan {
            app.launchEnvironment["REDAKTR_UI_FAIL_SCAN_FILENAME"] = fixtureURL.lastPathComponent
        } else {
            app.launchEnvironment["REDAKTR_UI_SEED_DETECTIONS"] = "1"
        }
        if seedWatchedScreenshot {
            let watchedFixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-watched-fixture.png")
            try makeFixturePNG(at: watchedFixtureURL)
            app.launchEnvironment["REDAKTR_UI_WATCHED_FIXTURE_PATH"] = watchedFixtureURL.path
        }
        if let uiTextObservation {
            app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = uiTextObservation
        }
        if seedManualDetection {
            app.launchEnvironment["REDAKTR_UI_SEED_MANUAL_DETECTION"] = "1"
        }
        if seedReviewDetection {
            app.launchEnvironment["REDAKTR_UI_SEED_REVIEW_DETECTION"] = "1"
        }
        if let exportURL {
            app.launchEnvironment["REDAKTR_UI_EXPORT_PATH"] = exportURL.path
        }
        if exportToAppTemp {
            app.launchEnvironment["REDAKTR_UI_EXPORT_TO_APP_TEMP"] = "1"
        }
        if resetHistory {
            app.launchEnvironment["REDAKTR_UI_RESET_SAFE_SHARE_HISTORY"] = "1"
        }
        app.launch()
        app.activate()

        let reviewState = failScan
            ? button("confirm-manual-review-button", in: app)
            : app.staticTexts["redaction-count-label"]
        XCTAssertTrue(
            reviewState.waitForExistence(timeout: 10),
            "Fixture review screen did not load.",
            file: file,
            line: line
        )

        return FixtureContext(app: app, tempDirectory: tempDirectory)
    }

    private func launchWithBatchFixtures(
        failSecondScan: Bool = false,
        seedDetectionsFirstItemOnly: Bool = false,
        seedMixedBatchCategories: Bool = false,
        batchExportRootURL: URL? = nil,
        batchExportToAppTemp: Bool = false,
        resetHistory: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FixtureContext {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-batch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let firstURL = tempDirectory.appendingPathComponent("redaktr-ui-batch-1.png")
        let secondURL = tempDirectory.appendingPathComponent("redaktr-ui-batch-2.png")
        try makeFixturePNG(at: firstURL)
        try makeFixturePNG(at: secondURL)

        let app = makeApp()
        app.launchEnvironment["REDAKTR_UI_TEST_MODE"] = "1"
        app.launchEnvironment["REDAKTR_UI_FIXTURE_PATH"] = firstURL.path
        app.launchEnvironment["REDAKTR_UI_BATCH_FIXTURE_PATHS"] = [firstURL.path, secondURL.path].joined(separator: "\t")
        if failSecondScan {
            app.launchEnvironment["REDAKTR_UI_FAIL_SCAN_FILENAME"] = secondURL.lastPathComponent
            app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = "Contact maya@example.com"
        } else {
            app.launchEnvironment["REDAKTR_UI_SEED_DETECTIONS"] = "1"
        }
        if seedDetectionsFirstItemOnly {
            app.launchEnvironment["REDAKTR_UI_SEED_DETECTIONS_FIRST_ITEM_ONLY"] = "1"
        }
        if seedMixedBatchCategories {
            app.launchEnvironment["REDAKTR_UI_SEED_MIXED_BATCH_CATEGORIES"] = "1"
        }
        if let batchExportRootURL {
            app.launchEnvironment["REDAKTR_UI_BATCH_EXPORT_ROOT_PATH"] = batchExportRootURL.path
        }
        if batchExportToAppTemp {
            app.launchEnvironment["REDAKTR_UI_BATCH_EXPORT_TO_APP_TEMP"] = "1"
        }
        if resetHistory {
            app.launchEnvironment["REDAKTR_UI_RESET_SAFE_SHARE_HISTORY"] = "1"
        }
        app.launch()
        app.activate()

        XCTAssertTrue(
            app.descendants(matching: .any)["batch-queue-sidebar"].waitForExistence(timeout: 12),
            "Fixture batch review screen did not load.",
            file: file,
            line: line
        )

        return FixtureContext(app: app, tempDirectory: tempDirectory)
    }

    private func launchWithDetectionSettingsFixture(
        customTerms: String? = "",
        customRegexes: String? = "",
        allowlist: String? = "",
        resetDetectionSettings: Bool = false,
        uiTextObservation: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FixtureContext {
        let tempDirectory = fixtureRoot
            .appendingPathComponent("redaktr-ui-detection-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fixtureURL = tempDirectory.appendingPathComponent("redaktr-ui-detection-settings.png")
        try makeDetectionSettingsFixturePNG(at: fixtureURL)

        let app = makeApp(
            customTerms: customTerms,
            customRegexes: customRegexes,
            allowlist: allowlist
        )
        app.launchEnvironment["REDAKTR_UI_FIXTURE_PATH"] = fixtureURL.path
        app.launchEnvironment["REDAKTR_UI_TEST_TEXT_OBSERVATION"] = uiTextObservation
            ?? "Project \(Self.customTermFixtureText) support ticket TICKET-3498"
        if resetDetectionSettings {
            app.launchEnvironment["REDAKTR_UI_RESET_DETECTION_SETTINGS"] = "1"
        }
        app.launch()
        app.activate()

        XCTAssertTrue(
            app.staticTexts["redaction-count-label"].waitForExistence(timeout: 10),
            "Detection settings fixture review screen did not load.",
            file: file,
            line: line
        )

        return FixtureContext(app: app, tempDirectory: tempDirectory)
    }

    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: identifier).element(boundBy: 0)
    }

    private func clickButton(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        clickElement(button(identifier, in: app), timeout: timeout, file: file, line: line)
    }

    private func clickElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        if element.isHittable {
            element.click()
            return
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func chooseReviewCommand(
        _ itemTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        chooseMenuCommand(menuTitle: "Review", itemTitle: itemTitle, in: app, file: file, line: line)
    }

    private func chooseMenuCommand(
        menuTitle: String,
        itemTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.activate()
        let menu = app.menuBars.menuBarItems[menuTitle].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Missing \(menuTitle) menu.", file: file, line: line)
        menu.click()

        let item = app.menuItems[itemTitle].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing \(itemTitle) menu item.", file: file, line: line)
        item.click()
    }

    private func assertMainTopControlsVisible(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let openButton = button("open-image-button", in: app)
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), file: file, line: line)
        let captureMenu = app.descendants(matching: .any)["capture-menu-button"].firstMatch
        XCTAssertTrue(captureMenu.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(captureMenu.frame.width, 80, "Capture menu should stay compact in the top bar.", file: file, line: line)
        let detectButton = button("detect-button", in: app)
        XCTAssertTrue(detectButton.exists, file: file, line: line)
        let clearButton = button("clear-current-review-button", in: app)
        XCTAssertTrue(clearButton.exists, file: file, line: line)
        let moreMenu = app.descendants(matching: .any)["more-actions-menu-button"].firstMatch
        XCTAssertTrue(moreMenu.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(moreMenu.frame.width, 80, "More menu should stay compact in the top bar.", file: file, line: line)

        let controls = [openButton, captureMenu, detectButton, clearButton, moreMenu]
        let baselineHeight = controls[0].frame.height
        for control in controls {
            XCTAssertGreaterThanOrEqual(control.frame.height, 30, "Top controls should keep a tappable height.", file: file, line: line)
            XCTAssertLessThanOrEqual(abs(control.frame.height - baselineHeight), 2, "Top controls should use the same visual height.", file: file, line: line)
        }

        let sortedControls = controls.sorted { $0.frame.minX < $1.frame.minX }
        for index in 1..<sortedControls.count {
            let gap = sortedControls[index].frame.minX - sortedControls[index - 1].frame.maxX
            XCTAssertGreaterThanOrEqual(gap, 6, "Top controls should not visually touch each other.", file: file, line: line)
        }
    }

    private func assertToolbarDropdownsOpen(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let captureButton = app.descendants(matching: .any)["capture-menu-button"].firstMatch
        XCTAssertTrue(captureButton.exists, file: file, line: line)
        captureButton.click()
        XCTAssertTrue(button("capture-area-menu-item", in: app).waitForExistence(timeout: 3), file: file, line: line)
        app.typeKey(.escape, modifierFlags: [])

        let moreButton = app.descendants(matching: .any)["more-actions-menu-button"].firstMatch
        XCTAssertTrue(moreButton.exists, file: file, line: line)
        moreButton.click()
        XCTAssertTrue(button("help-center-menu-item", in: app).waitForExistence(timeout: 3), file: file, line: line)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func installReminderExists(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.staticTexts["Install Redaktr in Applications"].waitForExistence(timeout: timeout)
            || app.alerts["Install Redaktr in Applications"].waitForExistence(timeout: timeout)
    }

    private func settingsEditor(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews[identifier].firstMatch
        if textView.exists {
            return textView
        }

        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private func XCTAssertRedactionCount(
        _ expected: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let count = button("redaction-count-value", in: app)
        XCTAssertTrue(count.waitForExistence(timeout: timeout), file: file, line: line)
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: count)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected redaction count '\(expected)', got '\(count.label)'.",
            file: file,
            line: line
        )
    }

    private func XCTAssertPolicyActionReason(
        _ identifier: String,
        contains expectedText: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let reason = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: timeout), file: file, line: line)
        let text = accessibleText(for: reason)
        XCTAssertTrue(
            text.contains(expectedText),
            "Expected policy action reason \(identifier) to contain '\(expectedText)', got '\(text)'.",
            file: file,
            line: line
        )
    }

    private func XCTAssertCompletionBanner(
        _ expectedText: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let banner = app.descendants(matching: .any)["completion-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: timeout), file: file, line: line)
        let found = waitUntil(timeout: timeout) {
            accessibleText(for: banner).localizedCaseInsensitiveContains(expectedText)
        }
        XCTAssertTrue(
            found,
            "Expected completion banner to contain '\(expectedText)', got '\(accessibleText(for: banner))'.",
            file: file,
            line: line
        )
    }

    private func clickSettingsTab(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let candidates = [
            app.buttons[title].firstMatch,
            app.radioButtons[title].firstMatch,
            app.descendants(matching: .any)[title].firstMatch
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 1) {
            clickElement(candidate, timeout: 1, file: file, line: line)
            return
        }

        XCTFail("Could not find settings tab \(title)", file: file, line: line)
    }

    private func openSettings(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        if app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5) {
            return
        }

        let appMenu = app.menuBars.menuBarItems["Redaktr"].firstMatch
        if appMenu.waitForExistence(timeout: 2) {
            appMenu.click()
            for title in ["Settings…", "Settings...", "Preferences…", "Preferences..."] {
                let item = app.menuItems[title].firstMatch
                if item.waitForExistence(timeout: 1) {
                    item.click()
                    if app.descendants(matching: .any)["custom-settings-view"].waitForExistence(timeout: 5) {
                        return
                    }
                }
            }
        }

        XCTFail("Could not open Settings", file: file, line: line)
    }

    private func clickControl(
        _ title: String,
        in element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let candidates = [
            element.checkBoxes[title].firstMatch,
            element.switches[title].firstMatch,
            element.radioButtons[title].firstMatch,
            element.buttons[title].firstMatch,
            element.menuItems[title].firstMatch,
            element.staticTexts[title].firstMatch,
            element.descendants(matching: .any)[title].firstMatch
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 1) {
            clickElement(candidate, timeout: 1, file: file, line: line)
            return
        }

        XCTFail("Could not find control \(title)", file: file, line: line)
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxScrolls: Int = 12
    ) -> Bool {
        if element.waitForExistence(timeout: 1) {
            return true
        }

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<maxScrolls {
            if scrollView.exists {
                scrollView.scroll(byDeltaX: 0, deltaY: -240)
            } else {
                app.scroll(byDeltaX: 0, deltaY: -240)
            }
            if element.waitForExistence(timeout: 0.5) {
                return true
            }
        }

        return false
    }

    private func makeApp(
        customTerms: String? = "",
        customRegexes: String? = "",
        allowlist: String? = "",
        policyPreset: String? = "",
        areaShortcutID: String? = nil,
        windowShortcutID: String? = nil,
        screenShortcutID: String? = nil,
        captureOutputModeID: String? = nil,
        captureOutputSafetyModeID: String? = nil,
        captureOutputRequiresNoReviewFindings: String? = nil,
        captureOutputFolderPath: String? = nil,
        captureOutputFolderDisplayName: String? = nil,
        screenshotWatchEnabled: String = "NO",
        screenshotWatchFolderPath: String = "",
        screenshotWatchFolderDisplayName: String = ""
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.appID)
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-screenshotWatchEnabled", screenshotWatchEnabled,
            "-screenshotWatchFolderPath", screenshotWatchFolderPath,
            "-screenshotWatchFolderDisplayName", screenshotWatchFolderDisplayName,
            "-clipboardProtectionEnabled", "NO",
            "-redaktrDidCompleteOnboardingV1", "YES",
            "-redaktrDidDismissGettingStartedV1", "NO"
        ]
        appendLaunchDefault("customDetectionTerms", value: customTerms, to: app)
        appendLaunchDefault("customDetectionRegexes", value: customRegexes, to: app)
        appendLaunchDefault("customDetectionAllowlist", value: allowlist, to: app)
        appendLaunchDefault("redactionPolicyPreset", value: policyPreset, to: app)
        appendLaunchDefault("redaktrCaptureShortcutArea", value: areaShortcutID, to: app)
        appendLaunchDefault("redaktrCaptureShortcutWindow", value: windowShortcutID, to: app)
        appendLaunchDefault("redaktrCaptureShortcutScreen", value: screenShortcutID, to: app)
        appendLaunchDefault("redaktrCaptureOutputMode", value: captureOutputModeID, to: app)
        appendLaunchDefault("redaktrCaptureOutputSafetyMode", value: captureOutputSafetyModeID, to: app)
        appendLaunchDefault(
            "redaktrCaptureOutputRequiresNoReviewFindings",
            value: captureOutputRequiresNoReviewFindings,
            to: app
        )
        appendLaunchDefault("redaktrCaptureOutputFolderPath", value: captureOutputFolderPath, to: app)
        appendLaunchDefault("redaktrCaptureOutputFolderDisplayName", value: captureOutputFolderDisplayName, to: app)
        app.launchEnvironment["REDAKTR_UI_TEST_MODE"] = "1"
        app.launchEnvironment["REDAKTR_UI_TEST_PASTEBOARD"] = pasteboardName.rawValue
        app.launchEnvironment["REDAKTR_UI_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["REDAKTR_UI_RESET_DETECTION_SETTINGS"] = "1"
        app.launchEnvironment["REDAKTR_UI_INSTALL_LOCATION_OVERRIDE"] = "/Applications/Redaktr.app"
        return app
    }

    private func appendLaunchDefault(_ key: String, value: String?, to app: XCUIApplication) {
        guard let value else { return }
        app.launchArguments += ["-\(key)", value]
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func accessibleText(for element: XCUIElement) -> String {
        [element.label, element.value as? String]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static let customTermFixtureText = "RedaktrUITestOnlyTerm"

    private func rgbaPixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var components = [UInt8](repeating: 0, count: 4)
        try components.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return components
    }

    private func makeFixturePNG(at url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 480,
            pixelsHigh: 300,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw FixtureError.imageCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 480, height: 300).fill()
        NSColor.black.setFill()
        NSString(string: "Contact user@example.com before sharing.")
            .draw(
                at: NSPoint(x: 56, y: 128),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 24),
                    .foregroundColor: NSColor.black
                ]
            )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw FixtureError.imageCreationFailed
        }

        try data.write(to: url, options: [.atomic])
    }

    private func makeDetectionSettingsFixturePNG(at url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 720,
            pixelsHigh: 260,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw FixtureError.imageCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 720, height: 260).fill()
        NSColor.black.setFill()
        NSString(string: "Project \(Self.customTermFixtureText) support ticket TICKET-3498")
            .draw(
                at: NSPoint(x: 48, y: 104),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: NSColor.black
                ]
            )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw FixtureError.imageCreationFailed
        }

        try data.write(to: url, options: [.atomic])
    }

}

private struct FixtureContext {
    let app: XCUIApplication
    let tempDirectory: URL
}

private enum FixtureError: Error {
    case imageCreationFailed
}
