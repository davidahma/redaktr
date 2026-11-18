import RedaktrCore
import XCTest

final class RedaktrCaptureTests: XCTestCase {
    func testCaptureModesExposeStableCommandOrder() {
        XCTAssertEqual(RedaktrCaptureMode.allCases.map(\.rawValue), ["screen", "window", "area"])
        XCTAssertEqual(RedaktrCaptureMode.allCases.map(\.commandTitle), [
            "Capture Entire Screen",
            "Capture Window...",
            "Capture Area..."
        ])
    }

    func testInteractiveCaptureModesAreExplicit() {
        XCTAssertFalse(RedaktrCaptureMode.screen.startsInteractiveSelection)
        XCTAssertTrue(RedaktrCaptureMode.window.startsInteractiveSelection)
        XCTAssertTrue(RedaktrCaptureMode.area.startsInteractiveSelection)
    }

    func testPermissionExplanationAvoidsInterceptionClaim() {
        XCTAssertTrue(RedaktrCaptureMode.permissionExplanation.contains("local temporary image"))
        XCTAssertTrue(RedaktrCaptureMode.permissionExplanation.contains("does not intercept"))
        XCTAssertTrue(RedaktrCaptureMode.permissionExplanation.contains("server"))
    }

    func testCaptureShortcutDefaultsAvoidAppleScreenshotShortcuts() {
        let defaults = RedaktrCaptureShortcutSettings.defaults

        XCTAssertEqual(defaults.choice(for: .area), .optionShift1)
        XCTAssertEqual(defaults.choice(for: .window), .optionShift2)
        XCTAssertEqual(defaults.choice(for: .screen), .optionShift3)
        XCTAssertEqual(defaults.choice(for: .area).modifierIDs, [.option, .shift])
        XCTAssertEqual(defaults.choice(for: .area).keyEquivalent, "1")
        XCTAssertEqual(defaults.choice(for: .window).keyEquivalent, "2")
        XCTAssertEqual(defaults.choice(for: .screen).keyEquivalent, "3")
        XCTAssertEqual(defaults.choice(for: .area).menuShortcutHint, "⌥⇧1")
        XCTAssertEqual(defaults.choice(for: .window).menuShortcutHint, "⌥⇧2")
        XCTAssertEqual(defaults.choice(for: .screen).menuShortcutHint, "⌥⇧3")
        XCTAssertFalse(defaults.hasConflicts)
    }

    func testCaptureShortcutSettingsDecodeStoredIDsThroughSharedDefaults() {
        let settings = RedaktrCaptureShortcutSettings(
            rawAreaID: RedaktrCaptureShortcutChoice.controlOption1.rawValue,
            rawWindowID: "unknown-window-shortcut",
            rawScreenID: nil
        )

        XCTAssertEqual(settings.choice(for: .area), .controlOption1)
        XCTAssertEqual(settings.choice(for: .window), RedaktrCaptureMode.window.defaultShortcutChoice)
        XCTAssertEqual(settings.choice(for: .screen), RedaktrCaptureMode.screen.defaultShortcutChoice)
    }

    func testCaptureShortcutStorageKeysMapModesInOneSharedPlace() {
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.shortcutChoiceKey(for: .area), .area)
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.shortcutChoiceKey(for: .window), .window)
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.shortcutChoiceKey(for: .screen), .screen)
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.area.rawValue, "redaktrCaptureShortcutArea")
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.window.rawValue, "redaktrCaptureShortcutWindow")
        XCTAssertEqual(RedaktrCaptureShortcutStorageKey.screen.rawValue, "redaktrCaptureShortcutScreen")
    }

    func testCaptureShortcutAlternatesExposeMenuHintsAndKeys() {
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption1.keyEquivalent, "1")
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption2.keyEquivalent, "2")
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption3.keyEquivalent, "3")
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption1.menuShortcutHint, "⌃⌥1")
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption2.menuShortcutHint, "⌃⌥2")
        XCTAssertEqual(RedaktrCaptureShortcutChoice.controlOption3.menuShortcutHint, "⌃⌥3")
        XCTAssertNil(RedaktrCaptureShortcutChoice.disabled.keyEquivalent)
        XCTAssertNil(RedaktrCaptureShortcutChoice.disabled.menuShortcutHint)
    }

    func testCaptureModesMapToStableHotKeyIdentifiers() {
        XCTAssertEqual(RedaktrCaptureMode.area.hotKeyIdentifier, 1)
        XCTAssertEqual(RedaktrCaptureMode.window.hotKeyIdentifier, 2)
        XCTAssertEqual(RedaktrCaptureMode.screen.hotKeyIdentifier, 3)
        XCTAssertEqual(RedaktrCaptureMode.mode(forHotKeyIdentifier: 1), .area)
        XCTAssertEqual(RedaktrCaptureMode.mode(forHotKeyIdentifier: 2), .window)
        XCTAssertEqual(RedaktrCaptureMode.mode(forHotKeyIdentifier: 3), .screen)
        XCTAssertNil(RedaktrCaptureMode.mode(forHotKeyIdentifier: 99))
    }

    func testCaptureShortcutSettingsDetectConflictsAndDisabledChoices() {
        var settings = RedaktrCaptureShortcutSettings.defaults
        settings.setChoice(.optionShift1, for: .window)
        settings.setChoice(.disabled, for: .screen)

        XCTAssertTrue(settings.hasConflicts)
        XCTAssertEqual(settings.conflictingChoices, [.optionShift1])
        XCTAssertEqual(settings.enabledShortcuts.count, 2)
        XCTAssertNil(RedaktrCaptureShortcutChoice.disabled.keyCode)
    }

    func testCaptureOutputDecisionKeepsExplicitReviewModeInReview() {
        let decision = RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(mode: .reviewInRedaktr),
            reviewFindingCount: 0
        )

        XCTAssertTrue(decision.shouldReviewInRedaktr)
        XCTAssertEqual(decision.mode, .reviewInRedaktr)
        XCTAssertEqual(decision.fallbackReason, .explicitReviewMode)
    }

    func testCaptureOutputDecisionHonorsReviewFirstSafetyMode() {
        let decision = RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(
                mode: .copyCleanedPNG,
                safetyMode: .reviewFirst
            ),
            reviewFindingCount: 0
        )

        XCTAssertTrue(decision.shouldReviewInRedaktr)
        XCTAssertEqual(decision.mode, .reviewInRedaktr)
        XCTAssertEqual(decision.fallbackReason, .reviewFirstMode)
    }

    func testCaptureOutputDecisionFallsBackWhenReviewFindingsExist() {
        let decision = RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(
                mode: .copyCleanedPNG,
                requiresNoReviewFindings: true
            ),
            reviewFindingCount: 2
        )

        XCTAssertTrue(decision.shouldReviewInRedaktr)
        XCTAssertEqual(decision.mode, .reviewInRedaktr)
        XCTAssertEqual(decision.fallbackReason, .reviewFindingsPresent(2))
    }

    func testCaptureOutputDecisionAllowsAutoOutputWhenStrictGatePasses() {
        let decision = RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(
                mode: .saveAndCopyCleanedPNG,
                requiresNoReviewFindings: true
            ),
            reviewFindingCount: 0
        )

        XCTAssertFalse(decision.shouldReviewInRedaktr)
        XCTAssertEqual(decision.mode, .saveAndCopyCleanedPNG)
        XCTAssertNil(decision.fallbackReason)
    }

    func testCaptureOutputDecisionCanAllowAutoOutputWithReviewFindingsWhenStrictGateOff() {
        let decision = RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(
                mode: .saveCleanedPNG,
                requiresNoReviewFindings: false
            ),
            reviewFindingCount: 1
        )

        XCTAssertFalse(decision.shouldReviewInRedaktr)
        XCTAssertEqual(decision.mode, .saveCleanedPNG)
        XCTAssertNil(decision.fallbackReason)
    }

    func testAutoCleanReceiptRouterUsesNotificationOnlyWhenBackgrounded() {
        XCTAssertEqual(RedaktrAutoCleanReceiptRouter.route(isAppActive: true), .inAppBanner)
        XCTAssertEqual(RedaktrAutoCleanReceiptRouter.route(isAppActive: false), .systemNotification)
        XCTAssertEqual(
            RedaktrAutoCleanReceiptRouter.route(isAppActive: false, notificationsAvailable: false),
            .inAppBanner
        )
    }

    func testBuildTrustEvaluatorClassifiesAmbientDistributionReadiness() {
        XCTAssertEqual(
            RedaktrBuildTrustEvaluator.assess(
                RedaktrBuildTrustInput(
                    isDebugBuild: false,
                    teamIdentifier: "34PBV2Y44H",
                    signingAuthority: "Developer ID Application: David Ahmann (34PBV2Y44H)",
                    gatekeeperAccepted: true
                )
            ).kind,
            .notarizedDeveloperID
        )

        XCTAssertEqual(
            RedaktrBuildTrustEvaluator.assess(
                RedaktrBuildTrustInput(
                    isDebugBuild: true,
                    teamIdentifier: "34PBV2Y44H",
                    signingAuthority: "Apple Development: David Ahmann",
                    gatekeeperAccepted: nil
                )
            ).kind,
            .developmentSigned
        )

        XCTAssertEqual(
            RedaktrBuildTrustEvaluator.assess(
                RedaktrBuildTrustInput(
                    isDebugBuild: false,
                    teamIdentifier: nil,
                    signingAuthority: "adhoc",
                    gatekeeperAccepted: nil
                )
            ).kind,
            .adHocOrUnsigned
        )

        XCTAssertEqual(
            RedaktrBuildTrustEvaluator.assess(
                RedaktrBuildTrustInput(
                    isDebugBuild: false,
                    teamIdentifier: "34PBV2Y44H",
                    signingAuthority: "Developer ID Application: David Ahmann (34PBV2Y44H)",
                    gatekeeperAccepted: false
                )
            ).kind,
            .gatekeeperRejected
        )
    }

    func testScreenshotProtectionStatusFlagsCaptureSaveModeWithoutFolder() throws {
        let items = ScreenshotProtectionStatusBuilder.build(
            input: ScreenshotProtectionStatusInput(
                captureOutputMode: .saveCleanedPNG,
                captureSaveFolderSelected: false,
                captureShortcutsEnabled: true,
                folderWatchEnabled: false,
                folderWatchFolderSelected: false,
                clipboardGuardEnabled: false,
                policyDisplayName: "",
                isPolicyManaged: false
            )
        )

        let capture = try XCTUnwrap(items.first { $0.rail == .redaktrCapture })
        XCTAssertEqual(capture.readiness, .needsSetup)
        XCTAssertTrue(capture.detail.contains("auto-save folder"))
    }

    func testScreenshotProtectionStatusFlagsCapturePermissionRequirement() throws {
        let items = ScreenshotProtectionStatusBuilder.build(
            input: ScreenshotProtectionStatusInput(
                captureOutputMode: .copyCleanedPNG,
                captureSaveFolderSelected: false,
                captureShortcutsEnabled: true,
                captureNeedsPermission: true,
                folderWatchEnabled: true,
                folderWatchFolderSelected: true,
                clipboardGuardEnabled: true,
                policyDisplayName: "Company Confidential",
                isPolicyManaged: false
            )
        )

        let capture = try XCTUnwrap(items.first { $0.rail == .redaktrCapture })
        XCTAssertEqual(capture.readiness, .needsPermission)
        XCTAssertTrue(capture.detail.contains("Screen Recording"))
    }

    func testScreenshotProtectionStatusReflectsAmbientRails() throws {
        let items = ScreenshotProtectionStatusBuilder.build(
            input: ScreenshotProtectionStatusInput(
                captureOutputMode: .copyCleanedPNG,
                captureSaveFolderSelected: false,
                captureShortcutsEnabled: false,
                folderWatchEnabled: true,
                folderWatchFolderSelected: true,
                clipboardGuardEnabled: true,
                policyDisplayName: "Company Confidential",
                isPolicyManaged: false
            )
        )

        let capture = try XCTUnwrap(items.first { $0.rail == .redaktrCapture })
        let folderWatch = try XCTUnwrap(items.first { $0.rail == .folderWatch })
        let clipboardGuard = try XCTUnwrap(items.first { $0.rail == .clipboardGuard })
        let policy = try XCTUnwrap(items.first { $0.rail == .policy })

        XCTAssertEqual(capture.readiness, .on)
        XCTAssertTrue(capture.detail.contains("Menu bar capture"))
        XCTAssertEqual(folderWatch.readiness, .on)
        XCTAssertEqual(clipboardGuard.readiness, .on)
        XCTAssertEqual(policy.readiness, .on)
        XCTAssertTrue(policy.detail.contains("Company Confidential"))
    }

    func testScreenshotProtectionStatusDistinguishesManagedPolicy() throws {
        let items = ScreenshotProtectionStatusBuilder.build(
            input: ScreenshotProtectionStatusInput(
                captureOutputMode: .reviewInRedaktr,
                captureSaveFolderSelected: false,
                captureShortcutsEnabled: true,
                folderWatchEnabled: false,
                folderWatchFolderSelected: true,
                clipboardGuardEnabled: false,
                policyDisplayName: "Local preset",
                isPolicyManaged: true
            )
        )

        let folderWatch = try XCTUnwrap(items.first { $0.rail == .folderWatch })
        let policy = try XCTUnwrap(items.first { $0.rail == .policy })

        XCTAssertEqual(folderWatch.readiness, .off)
        XCTAssertTrue(folderWatch.detail.contains("paused"))
        XCTAssertEqual(policy.readiness, .on)
        XCTAssertEqual(policy.detail, "Managed by team policy.")
    }
}
