import Foundation
import AppKit
import RedaktrCore
import SwiftUI

@main
struct RedaktrApp: App {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.areaKey) private var areaShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultAreaID
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.windowKey) private var windowShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultWindowID
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.screenKey) private var screenShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultScreenID

    private static let mainWindowID = "redaktr-main-window"

    private var captureShortcutSettings: RedaktrCaptureShortcutSettings {
        RedaktrCaptureShortcutSettingsStorage.settings(
            areaID: areaShortcutID,
            windowID: windowShortcutID,
            screenID: screenShortcutID
        )
    }

    init() {
        ScreenshotWatchRiskNotifier.configureNotificationHandling()
        RedaktrUITestEnvironment.resetDefaultsIfRequested()
    }

    var body: some Scene {
        WindowGroup("Redaktr", id: Self.mainWindowID) {
            ContentView()
                .frame(minWidth: 1180, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Close Current Review") {
                    NotificationCenter.default.post(name: .redaktrCloseCurrentReview, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Import Clipboard Image") {
                    NotificationCenter.default.post(name: .redaktrImportClipboardImage, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            CommandMenu("Review") {
                Button("Preview Cleaned Output") {
                    NotificationCenter.default.post(name: .redaktrToggleOutputPreview, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Export Cleaned Copy") {
                    NotificationCenter.default.post(name: .redaktrExportCleanedImage, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Copy Cleaned PNG") {
                    NotificationCenter.default.post(name: .redaktrCopyCleanedImage, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Redact All Findings") {
                    NotificationCenter.default.post(name: .redaktrRedactAllFindings, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Make All Findings Visible") {
                    NotificationCenter.default.post(name: .redaktrMakeAllFindingsVisible, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Divider()

                Button("Delete Selected Manual Redaction") {
                    NotificationCenter.default.post(name: .redaktrDeleteSelectedManualRedaction, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Button("Undo Manual Edit") {
                    NotificationCenter.default.post(name: .redaktrUndoManualEdit, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo Manual Edit") {
                    NotificationCenter.default.post(name: .redaktrRedoManualEdit, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Capture") {
                captureCommandButton(.screen)
                captureCommandButton(.window)
                captureCommandButton(.area)
            }

            CommandGroup(replacing: .help) {
                Button("Redaktr Help Center") {
                    NotificationCenter.default.post(name: .redaktrShowHelpCenter, object: nil)
                }

                Button("Show Quick Start") {
                    NotificationCenter.default.post(name: .redaktrShowOnboarding, object: nil)
                }
            }
        }

        MenuBarExtra {
            Label("Redaktr", systemImage: "camera.viewfinder")
                .font(.headline)
                .accessibilityIdentifier("menu-bar-redaktr-title")

            Divider()

            Button {
                showMainWindow()
            } label: {
                Label("Show Redaktr", systemImage: "macwindow")
            }
            .accessibilityIdentifier("menu-bar-show-redaktr")

            Divider()

            Button {
                requestCapture(.area)
            } label: {
                Label("Capture Area", systemImage: RedaktrCaptureMode.area.systemImage)
            }
            .modifier(CaptureKeyboardShortcutModifier(choice: menuShortcutChoice(for: .area)))
            .accessibilityIdentifier("menu-bar-capture-area")

            Button {
                requestCapture(.window)
            } label: {
                Label("Capture Window", systemImage: RedaktrCaptureMode.window.systemImage)
            }
            .modifier(CaptureKeyboardShortcutModifier(choice: menuShortcutChoice(for: .window)))
            .accessibilityIdentifier("menu-bar-capture-window")

            Button {
                requestCapture(.screen)
            } label: {
                Label("Capture Screen", systemImage: RedaktrCaptureMode.screen.systemImage)
            }
            .modifier(CaptureKeyboardShortcutModifier(choice: menuShortcutChoice(for: .screen)))
            .accessibilityIdentifier("menu-bar-capture-screen")

            Divider()

            Button {
                postToMainWindow(.redaktrImportClipboardImage)
            } label: {
                Label("Scan Clipboard Image", systemImage: "doc.on.clipboard")
            }
            .accessibilityIdentifier("menu-bar-scan-clipboard-image")

            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu-bar-open-settings")

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Redaktr", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityIdentifier("menu-bar-quit-redaktr")
        } label: {
            Label("Redaktr", systemImage: "camera.viewfinder")
                .accessibilityLabel("Redaktr")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            RedaktrSettingsView()
        }
    }

    @ViewBuilder
    private func captureCommandButton(_ mode: RedaktrCaptureMode) -> some View {
        Button(mode.commandTitle) {
            requestCapture(mode)
        }
        .modifier(CaptureKeyboardShortcutModifier(choice: menuShortcutChoice(for: mode)))
    }

    private func menuShortcutChoice(for mode: RedaktrCaptureMode) -> RedaktrCaptureShortcutChoice {
        let choice = captureShortcutSettings.choice(for: mode)
        if !choice.isEnabled || captureShortcutSettings.conflictingChoices.contains(choice) {
            return .disabled
        }
        return choice
    }

    private func requestCapture(_ mode: RedaktrCaptureMode) {
        if redaktrMainWindowIfAvailable() == nil {
            openWindow(id: Self.mainWindowID)
            DispatchQueue.main.async {
                NSApp.hide(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .redaktrCaptureRequested, object: mode)
        }
    }

    private func postToMainWindow(_ name: Notification.Name, object: Any? = nil) {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: name, object: object)
        }
    }

    private func showMainWindow() {
        if redaktrMainWindowIfAvailable() == nil {
            openWindow(id: Self.mainWindowID)
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            focusMainWindowIfAvailable()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusMainWindowIfAvailable()
        }
    }

}

@MainActor
func focusMainWindowIfAvailable() {
    let candidate = redaktrMainWindowIfAvailable() ?? NSApp.windows.first { window in
        window.canBecomeMain && window.level == .normal
    }

    guard let window = candidate else { return }
    if window.isMiniaturized {
        window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
}

@MainActor
private func redaktrMainWindowIfAvailable() -> NSWindow? {
    NSApp.windows.first { window in
        window.title == "Redaktr" && window.canBecomeMain
    }
}

private struct CaptureKeyboardShortcutModifier: ViewModifier {
    let choice: RedaktrCaptureShortcutChoice

    @ViewBuilder
    func body(content: Content) -> some View {
        if let keyEquivalent = choice.swiftUIKeyEquivalent {
            content.keyboardShortcut(keyEquivalent, modifiers: choice.swiftUIEventModifiers)
        } else {
            content
        }
    }
}

private extension RedaktrCaptureShortcutChoice {
    var swiftUIKeyEquivalent: KeyEquivalent? {
        switch keyEquivalent {
        case "1":
            return "1"
        case "2":
            return "2"
        case "3":
            return "3"
        default:
            return nil
        }
    }

    var swiftUIEventModifiers: EventModifiers {
        modifierIDs.reduce(EventModifiers()) { modifiers, modifier in
            switch modifier {
            case .control:
                return modifiers.union(.control)
            case .option:
                return modifiers.union(.option)
            case .shift:
                return modifiers.union(.shift)
            }
        }
    }
}

extension Notification.Name {
    static let redaktrCloseCurrentReview = Notification.Name("redaktrCloseCurrentReview")
    static let redaktrImportClipboardImage = Notification.Name("redaktrImportClipboardImage")
    static let redaktrCustomDetectionSettingsDidChange = Notification.Name("redaktrCustomDetectionSettingsDidChange")
    static let redaktrCustomDetectionSettingsRescanCompleted = Notification.Name("redaktrCustomDetectionSettingsRescanCompleted")
    static let redaktrOpenDetectionSettings = Notification.Name("redaktrOpenDetectionSettings")
    static let redaktrScreenshotWatchSettingsDidChange = Notification.Name("redaktrScreenshotWatchSettingsDidChange")
    static let redaktrClipboardProtectionSettingsDidChange = Notification.Name("redaktrClipboardProtectionSettingsDidChange")
    static let redaktrCaptureShortcutSettingsDidChange = Notification.Name("redaktrCaptureShortcutSettingsDidChange")
    static let redaktrCaptureRequested = Notification.Name("redaktrCaptureRequested")
    static let redaktrOpenLatestWatchedScreenshot = Notification.Name("redaktrOpenLatestWatchedScreenshot")
    static let redaktrShowHelpCenter = Notification.Name("redaktrShowHelpCenter")
    static let redaktrShowOnboarding = Notification.Name("redaktrShowOnboarding")
    static let redaktrToggleOutputPreview = Notification.Name("redaktrToggleOutputPreview")
    static let redaktrExportCleanedImage = Notification.Name("redaktrExportCleanedImage")
    static let redaktrCopyCleanedImage = Notification.Name("redaktrCopyCleanedImage")
    static let redaktrRedactAllFindings = Notification.Name("redaktrRedactAllFindings")
    static let redaktrMakeAllFindingsVisible = Notification.Name("redaktrMakeAllFindingsVisible")
    static let redaktrDeleteSelectedManualRedaction = Notification.Name("redaktrDeleteSelectedManualRedaction")
    static let redaktrUndoManualEdit = Notification.Name("redaktrUndoManualEdit")
    static let redaktrRedoManualEdit = Notification.Name("redaktrRedoManualEdit")
}
