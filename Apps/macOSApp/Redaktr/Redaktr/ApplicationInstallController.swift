import AppKit
import OSLog
import RedaktrCore
import SwiftUI

@MainActor
final class ApplicationInstallController: ObservableObject {
    @Published var isShowingInstallReminder = false

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.dahmann.redak", category: "install")
    private var didEvaluate = false

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    @discardableResult
    func evaluateOnLaunch(isUITestMode: Bool) -> Bool {
        guard !didEvaluate else { return isShowingInstallReminder }
        didEvaluate = true

        let environment = ProcessInfo.processInfo.environment
        let overridePath = isUITestMode ? environment["REDAKTR_UI_INSTALL_LOCATION_OVERRIDE"] : nil
        let hasOverride = overridePath?.isEmpty == false
        let appBundleURL = hasOverride
            ? URL(fileURLWithPath: overridePath!, isDirectory: true).standardizedFileURL
            : Bundle.main.bundleURL.standardizedFileURL
        let hasDismissedPrompt = defaults.bool(forKey: AppInstallLocation.dismissedPreferenceKey)

        let shouldPrompt = AppInstallLocation.shouldPromptToMove(
            appBundlePath: appBundleURL.path,
            homeDirectoryPath: fileManager.homeDirectoryForCurrentUser.path,
            hasDismissedPrompt: hasDismissedPrompt,
            isUITestMode: isUITestMode,
            allowsUITestOverride: hasOverride
        )

        logger.notice(
            """
            Evaluated install location path=\(appBundleURL.path, privacy: .public) \
            shouldPrompt=\(shouldPrompt, privacy: .public) \
            translocated=\(AppInstallLocation.isLikelyTranslocated(appBundlePath: appBundleURL.path), privacy: .public) \
            dismissed=\(hasDismissedPrompt, privacy: .public) \
            uiTest=\(isUITestMode, privacy: .public) \
            override=\(hasOverride, privacy: .public)
            """
        )

        isShowingInstallReminder = shouldPrompt
        return shouldPrompt
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        isShowingInstallReminder = false
    }

    func dismissForNow() {
        isShowingInstallReminder = false
    }

    func dismissPermanently() {
        defaults.set(true, forKey: AppInstallLocation.dismissedPreferenceKey)
        isShowingInstallReminder = false
    }
}

struct ApplicationInstallPresentationModifier: ViewModifier {
    @ObservedObject var controller: ApplicationInstallController
    let onPromptResolved: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Install Redaktr in Applications", isPresented: $controller.isShowingInstallReminder) {
                Button("Open Applications Folder") {
                    controller.openApplicationsFolder()
                    onPromptResolved()
                }
                .accessibilityIdentifier("install-reminder-open-applications-button")

                Button("Not Now", role: .cancel) {
                    controller.dismissForNow()
                    onPromptResolved()
                }
                .accessibilityIdentifier("install-reminder-not-now-button")

                Button("Don't Ask Again", role: .destructive) {
                    controller.dismissPermanently()
                    onPromptResolved()
                }
                .accessibilityIdentifier("install-reminder-dismiss-permanently-button")
            } message: {
                Text("For best results, drag Redaktr.app into the Applications folder from the installer window, then open it from there.")
            }
    }
}
