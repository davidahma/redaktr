import RedaktrCore
import XCTest

final class AppInstallLocationTests: XCTestCase {
    private let home = "/Users/tester"

    func testInstalledLocationsDoNotPrompt() {
        XCTAssertFalse(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Applications/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))

        XCTAssertFalse(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/System/Volumes/Data/Applications/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))

        XCTAssertFalse(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Applications/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))
    }

    func testDownloadsAndTranslocatedCopiesPrompt() {
        XCTAssertTrue(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Downloads/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))

        XCTAssertTrue(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Applications Backup/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))

        XCTAssertTrue(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/private/var/folders/abc/AppTranslocation/123/d/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: false
        ))
        XCTAssertTrue(AppInstallLocation.isLikelyTranslocated(
            appBundlePath: "/private/var/folders/abc/AppTranslocation/123/d/Redaktr.app"
        ))
    }

    func testDismissalAndUITestModeSuppressPrompt() {
        XCTAssertFalse(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Downloads/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: true,
            isUITestMode: false
        ))

        XCTAssertFalse(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Downloads/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: true
        ))

        XCTAssertTrue(AppInstallLocation.shouldPromptToMove(
            appBundlePath: "/Users/tester/Downloads/Redaktr.app",
            homeDirectoryPath: home,
            hasDismissedPrompt: false,
            isUITestMode: true,
            allowsUITestOverride: true
        ))
    }
}
