import AppKit
import RedaktrCore
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

enum RedaktrSettingsStorage {
    static let customTermsKey = "customDetectionTerms"
    static let customRegexesKey = "customDetectionRegexes"
    static let allowlistKey = "customDetectionAllowlist"
    static let policyPresetKey = "redactionPolicyPreset"
    static let policySourceKey = "redaktrPolicySource"
    static let policyLockKey = "redaktrPolicyLock"
    static let detectorCategoryPreferencesKey = "redaktrDetectorCategoryPreferences"

    static func configuration(
        customTermsText: String,
        customRegexesText: String,
        allowlistText: String,
        policyPresetID: String = "",
        detectorCategoryPreferencesData: Data = Data()
    ) -> CustomDetectionConfiguration {
        CustomDetectionConfiguration(
            terms: entries(from: customTermsText),
            regexes: entries(from: customRegexesText),
            allowlist: entries(from: allowlistText),
            policyConfiguration: RedactionPolicyConfiguration(presetRawValue: policyPresetID),
            detectorCategoryPreferences: detectorCategoryPreferences(from: detectorCategoryPreferencesData)
        )
    }

    static func detectorCategoryPreferences(from data: Data) -> DetectorCategoryPreferences {
        guard !data.isEmpty,
              let preferences = try? JSONDecoder().decode(DetectorCategoryPreferences.self, from: data)
        else {
            return .allEnabled
        }
        return preferences
    }

    static func detectorCategoryPreferencesData(_ preferences: DetectorCategoryPreferences) -> Data {
        (try? JSONEncoder().encode(preferences)) ?? Data()
    }

    private static func entries(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum SafeShareHistorySettingsStorage {
    static let historyKey = "safeShareHistoryStore"
    static let historyLimit = 50

    static var store: SafeShareHistoryStore {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let store = try? JSONDecoder().decode(SafeShareHistoryStore.self, from: data)
        else {
            return SafeShareHistoryStore()
        }

        return store
    }

    static func append(_ record: SafeShareHistoryRecord) {
        var store = store
        store.append(record, limit: historyLimit)
        save(store)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private static func save(_ store: SafeShareHistoryStore) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

struct RedaktrSettingsView: View {
    @AppStorage(RedaktrSettingsStorage.customTermsKey) private var customTermsText = ""
    @AppStorage(RedaktrSettingsStorage.customRegexesKey) private var customRegexesText = ""
    @AppStorage(RedaktrSettingsStorage.allowlistKey) private var allowlistText = ""
    @AppStorage(RedaktrSettingsStorage.policyPresetKey) private var policyPresetID = ""
    @AppStorage(RedaktrSettingsStorage.policySourceKey) private var policySourceID = PolicySource.local.rawValue
    @AppStorage(RedaktrSettingsStorage.policyLockKey) private var policyLockData = Data()
    @AppStorage(RedaktrSettingsStorage.detectorCategoryPreferencesKey) private var detectorCategoryPreferencesData = Data()
    @AppStorage(ScreenshotWatchSettingsStorage.isEnabledKey) private var isScreenshotWatchEnabled = false
    @AppStorage(ScreenshotWatchSettingsStorage.folderDisplayNameKey) private var screenshotWatchFolderDisplayName = ""
    @AppStorage(ScreenshotWatchSettingsStorage.folderPathKey) private var screenshotWatchFolderPath = ""
    @AppStorage(ClipboardProtectionSettingsStorage.isEnabledKey) private var isClipboardProtectionEnabled = false
    @AppStorage(ClipboardProtectionSettingsStorage.replacementModeKey) private var clipboardReplacementModeID = ClipboardProtectionReplacementMode.pauseIfUnsure.rawValue
    @AppStorage(RedaktrCaptureOutputSettingsStorage.modeKey) private var captureOutputModeID = RedaktrCaptureOutputMode.reviewInRedaktr.rawValue
    @AppStorage(RedaktrCaptureOutputSettingsStorage.safetyModeKey) private var captureOutputSafetyModeID = RedaktrAutoCleanSafetyMode.pauseIfUnsure.rawValue
    @AppStorage(RedaktrCaptureOutputSettingsStorage.requiresNoReviewFindingsKey) private var captureOutputRequiresNoReviewFindings = true
    @AppStorage(RedaktrCaptureOutputSettingsStorage.folderDisplayNameKey) private var captureOutputFolderDisplayName = ""
    @AppStorage(RedaktrCaptureOutputSettingsStorage.folderPathKey) private var captureOutputFolderPath = ""
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.areaKey) private var areaShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultAreaID
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.windowKey) private var windowShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultWindowID
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.screenKey) private var screenShortcutID = RedaktrCaptureShortcutSettingsStorage.defaultScreenID
    @AppStorage(RedaktrCaptureShortcutSettingsStorage.registrationStatusKey) private var captureShortcutRegistrationStatus = ""
    @State private var statusText = ""
    @State private var screenshotWatchStatusText = ""
    @State private var showsNotificationSettingsRecovery = false
    @State private var clipboardProtectionStatusText = ""
    @State private var detectionSettingsStatusText = ""
    @State private var historyStore = SafeShareHistoryStore()
    @State private var selectedSettingsTab: SettingsTab = .detection
    @FocusState private var focusedEditor: SettingsEditor?

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case detection
        case protection
        case privacy
        case help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .detection: "Detection"
            case .protection: "Protection"
            case .privacy: "Privacy"
            case .help: "Help"
            }
        }

        var systemImage: String {
            switch self {
            case .detection: "scope"
            case .protection: "shield"
            case .privacy: "lock"
            case .help: "questionmark.circle"
            }
        }
    }

    private enum SettingsAnchor {
        static let top = "settings-top"
        static let folderWatch = "settings-folder-watch"
        static let clipboardProtection = "settings-clipboard-protection"
        static let captureOutput = "settings-capture-output"
    }

    private var configuration: CustomDetectionConfiguration {
        RedaktrSettingsStorage.configuration(
            customTermsText: customTermsText,
            customRegexesText: customRegexesText,
            allowlistText: allowlistText,
            policyPresetID: policyPresetID,
            detectorCategoryPreferencesData: detectorCategoryPreferencesData
        )
    }

    private var detectorCategoryPreferences: DetectorCategoryPreferences {
        RedaktrSettingsStorage.detectorCategoryPreferences(from: detectorCategoryPreferencesData)
    }

    private var captureShortcutSettings: RedaktrCaptureShortcutSettings {
        RedaktrCaptureShortcutSettingsStorage.settings(
            areaID: areaShortcutID,
            windowID: windowShortcutID,
            screenID: screenShortcutID
        )
    }

    private var screenshotProtectionStatusItems: [ScreenshotProtectionStatusItem] {
        ScreenshotProtectionStatusBuilder.build(
            input: ScreenshotProtectionStatusInput(
                captureOutputMode: captureOutputMode,
                captureSaveFolderSelected: !captureOutputFolderPath.isEmpty,
                captureShortcutsEnabled: !captureShortcutSettings.enabledShortcuts.isEmpty,
                captureNeedsPermission: !CGPreflightScreenCaptureAccess(),
                folderWatchEnabled: isScreenshotWatchEnabled,
                folderWatchFolderSelected: !screenshotWatchFolderPath.isEmpty,
                clipboardGuardEnabled: isClipboardProtectionEnabled,
                policyDisplayName: selectedPreset?.title ?? "",
                isPolicyManaged: isPolicyManaged
            )
        )
    }

    private var selectedPreset: RedactionPolicyPreset? {
        guard let presetID = RedactionPolicyPresetID.normalized(rawValue: policyPresetID) else { return nil }
        return RedactionPolicyCatalog.preset(presetID)
    }

    private var policySource: PolicySource {
        PolicySource(rawValue: policySourceID) ?? .local
    }

    private var policyLock: PolicyLock {
        guard !policyLockData.isEmpty,
              let decoded = try? JSONDecoder().decode(PolicyLock.self, from: policyLockData)
        else {
            return PolicyLock()
        }
        return decoded
    }

    private var isPolicyManaged: Bool {
        policySource == .managed
    }

    private var policySourceLabel: String {
        isPolicyManaged ? "Managed by team policy" : "Imported policy"
    }

    private var policySourceSystemImage: String {
        isPolicyManaged ? "lock.shield" : "square.and.arrow.down"
    }

    private var policySourceColor: Color {
        isPolicyManaged ? .secondary : .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Form {
                if selectedSettingsTab == .detection {
                    Section("Policy Preset") {
                SettingsSectionHelpButton(
                    title: "Policy Preset",
                    help: "Choose a local policy preset for common sharing contexts. Company-confidential policies only match visible labels or configured terms."
                )

                Picker("Share preset", selection: $policyPresetID) {
                    Text("Current defaults").tag("")
                    ForEach(RedactionPolicyCatalog.presets) { preset in
                        Text(preset.title).tag(preset.id.rawValue)
                    }
                }
                .disabled(policyLock.isLocked(.policyPreset))
                .accessibilityIdentifier("policy-preset-picker")

                if policySource != .local {
                    Label(policySourceLabel, systemImage: policySourceSystemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(policySourceColor)
                        .accessibilityIdentifier("policy-source-label")
                }

                Text(selectedPreset?.summary ?? "Use Redaktr's built-in detector defaults without preset overrides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("policy-preset-summary")

                Text("Company-confidential policies match visible labels or configured terms and regexes. They do not provide semantic classification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("policy-claim-boundary-copy")

                Text("Policy presets group detectors into Secrets, Personal data, Financial data, Government IDs, Company confidential, Visual content, and Custom policy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("policy-pack-summary-copy")
	                    }
	                    .id(SettingsAnchor.top)
	            }

	                if selectedSettingsTab == .detection {
	                    Section("Custom Redactions") {
	                SettingsSectionHelpButton(
	                    title: "Custom Redactions",
	                    help: "Add one term or regex per line. Open images re-scan automatically after detection settings change."
	                )

	                SettingsTextEditor(
	                    title: "Terms",
	                    text: $customTermsText,
	                    focusedEditor: $focusedEditor,
	                    editor: .customTerms,
	                    accessibilityIdentifier: "custom-terms-editor",
	                    isDisabled: policyLock.isLocked(.customTerms)
	                )

	                SettingsTextEditor(
	                    title: "Regexes",
	                    text: $customRegexesText,
	                    focusedEditor: $focusedEditor,
	                    editor: .customRegexes,
	                    accessibilityIdentifier: "custom-regexes-editor",
	                    isDisabled: policyLock.isLocked(.customRegexes)
	                )

	                if !configuration.invalidRegexPatterns.isEmpty {
	                    Text("Invalid regexes are ignored: \(configuration.invalidRegexPatterns.joined(separator: ", "))")
	                        .font(.caption)
	                        .foregroundStyle(.orange)
	                        .fixedSize(horizontal: false, vertical: true)
	                }

	                if !detectionSettingsStatusText.isEmpty {
	                    Text(detectionSettingsStatusText)
	                        .font(.caption)
	                        .foregroundStyle(.green)
	                        .fixedSize(horizontal: false, vertical: true)
	                        .accessibilityIdentifier("detection-settings-status")
	                }
	                    }

	                    Section("Allowlist") {
	                SettingsSectionHelpButton(
	                    title: "Allowlist",
	                    help: "Known-safe strings suppress matching default and custom detections on this Mac."
	                )

	                SettingsTextEditor(
	                    title: "Known-Safe Strings",
	                    text: $allowlistText,
	                    focusedEditor: $focusedEditor,
	                    editor: .allowlist,
	                    accessibilityIdentifier: "allowlist-editor",
	                    isDisabled: policyLock.isLocked(.allowlist)
	                )
	                    }

	                    Section("Built-in Detectors") {
	                SettingsSectionHelpButton(
	                    title: "Built-in Detectors",
                    help: "Set detector families to Redact, Review, or Off for future scans. Custom terms, regexes, and allowlists stay local to this Mac."
                )

                ForEach(DetectorCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.displayName)
                                    .font(.body)

                                Text(category.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            DetectorCategoryDispositionControl(
                                category: category,
                                selection: detectorCategoryDispositionBinding(for: category)
                            )
                        }

                        Text(detectorCategoryDispositionBinding(for: category).wrappedValue.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("detector-category-row-\(category.rawValue)")
                }

                DisclosureGroup("Advanced detector details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Built-in detectors use local OCR text, local Vision observations, and deterministic patterns. They do not classify screenshot meaning semantically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("High-entropy strings are noisy by nature. Redaktr downgrades generic matches to Check and suppresses common deployment tags, branch names, labels, and paths unless strong secret context is visible.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("advanced-detector-details")
                    }
                }

                if selectedSettingsTab == .protection {
                    Section("Screenshot Protection") {
                SettingsSectionHelpButton(
                    title: "Screenshot Protection",
                    help: "See the local protection pipeline for screenshots as they are captured, saved, copied, or pasted."
                )

                Text("One local pipeline for screenshots: Capture, Folder Watch, Clipboard Guard, and Policy. Use it before screenshots leave your Mac for AI chat, Slack, email, tickets, or docs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screenshot-protection-ai-copy")

                if let buildTrustWarning {
                    Label(buildTrustWarning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build-trust-warning")
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(screenshotProtectionStatusItems) { item in
                        ScreenshotProtectionStatusRow(
                            item: item,
                            actionTitle: protectionStatusActionTitle(for: item.rail),
                            action: {
                                openProtectionStatusTarget(item.rail, proxy: proxy)
                            }
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("screenshot-protection-status-section")
                    }
                    .id(SettingsAnchor.top)
                }

                if selectedSettingsTab == .protection {
                    Section("Screenshot Folder Watch") {
                SettingsSectionHelpButton(
                    title: "Screenshot Folder Watch",
                    help: "Watch scans new images after they are saved in the selected folder. Redaktr never edits source screenshots."
                )

                Toggle(isOn: Binding(get: { isScreenshotWatchEnabled }, set: setScreenshotWatchEnabled)) {
                    Text("Watch selected folder")
                }
                .disabled(screenshotWatchFolderPath.isEmpty)
                .accessibilityIdentifier("screenshot-watch-enable-toggle")

                Text(screenshotWatchFolderSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screenshot-watch-folder-summary")

                HStack {
                    Button(action: watchDesktopFolder) {
                        Label("Desktop", systemImage: "desktopcomputer")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("screenshot-watch-desktop-button")

                    Button(action: watchScreenshotsFolder) {
                        Label("Screenshots", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("screenshot-watch-screenshots-button")

                    Button(action: chooseScreenshotWatchFolder) {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("screenshot-watch-choose-folder-button")

                    Spacer()

                    Button(role: .destructive, action: stopWatchingScreenshots) {
                        Label("Stop", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.redaktr(.destructive, minWidth: 88))
                    .disabled(screenshotWatchFolderPath.isEmpty)
                    .accessibilityIdentifier("screenshot-watch-stop-button")
                }

                Text("Redaktr watches screenshots after they are saved. It does not intercept Apple's native screenshot shortcuts before capture, and it never modifies the source file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screenshot-watch-boundary-copy")

                Text(screenshotWatchStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("screenshot-watch-status")
                    .accessibilityLabel(screenshotWatchStatusText)
                    .accessibilityValue(screenshotWatchStatusText)

                if showsNotificationSettingsRecovery {
                    Button(action: ScreenshotWatchRiskNotifier.openNotificationSettings) {
                        Label("Open Notification Settings", systemImage: "bell.badge")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("screenshot-watch-open-notification-settings-button")
                }
                    }
                    .id(SettingsAnchor.folderWatch)

                    Section("Clipboard Protection") {
                        SettingsSectionHelpButton(
                            title: "Clipboard Protection",
                            help: "Clipboard Protection scans image clipboard changes only and uses the same AutoClean safety modes as Redaktr Capture."
                        )

                        Toggle(isOn: Binding(get: { isClipboardProtectionEnabled }, set: setClipboardProtectionEnabled)) {
                            Text("Monitor clipboard images")
                        }
                        .accessibilityIdentifier("clipboard-protection-enable-toggle")

                        Picker("AutoClean mode", selection: $clipboardReplacementModeID) {
                            ForEach(ClipboardProtectionReplacementMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .disabled(!isClipboardProtectionEnabled)
                        .accessibilityIdentifier("clipboard-protection-mode-picker")

                        Text("Image-only. Redaktr checks whether the clipboard contains a supported image and never monitors text clipboard contents by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("clipboard-protection-boundary-copy")

                        Text(clipboardProtectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("clipboard-protection-summary")

                        Text(clipboardProtectionStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("clipboard-protection-status")
                            .accessibilityLabel(clipboardProtectionStatusText)
                            .accessibilityValue(clipboardProtectionStatusText)
                    }
                    .id(SettingsAnchor.clipboardProtection)

                    Section("Capture Output") {
                        SettingsSectionHelpButton(
                            title: "Capture Output",
                            help: "Choose what Redaktr Capture does after a screenshot is scanned. AutoClean can pause for review when findings need a human check."
                        )

                        Picker("Capture destination", selection: $captureOutputModeID) {
                            ForEach(RedaktrCaptureOutputMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .accessibilityIdentifier("capture-output-mode-picker")

                        Picker("AutoClean mode", selection: $captureOutputSafetyModeID) {
                            ForEach(RedaktrAutoCleanSafetyMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .accessibilityIdentifier("capture-output-safety-mode-picker")

                        Text(captureOutputSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("capture-output-summary")

                        Text("Redaktr Capture creates a temporary local image for scanning, then discards it. Copy and save modes write only the cleaned PNG.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("capture-output-temporary-copy")

                        HStack {
                            Button(action: chooseCaptureOutputFolder) {
                                Label("Choose Save Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.redaktr(.secondary))
                            .accessibilityIdentifier("capture-output-choose-folder-button")

                            Button(role: .destructive, action: clearCaptureOutputFolder) {
                                Label("Clear", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.redaktr(.destructive, minWidth: 88))
                            .disabled(captureOutputFolderPath.isEmpty)
                            .accessibilityIdentifier("capture-output-clear-folder-button")
                        }

                        Text(captureOutputFolderSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("capture-output-folder-summary")
                    }
                    .id(SettingsAnchor.captureOutput)

                    Section("Capture Shortcuts") {
                SettingsSectionHelpButton(
                    title: "Capture Shortcuts",
                    help: "Configure Redaktr-owned global shortcuts for safer capture. Redaktr does not intercept Apple's native Cmd-Shift screenshot shortcuts."
                )

                Text("Defaults: Option-Shift-1 captures an area, Option-Shift-2 captures a window, and Option-Shift-3 captures the screen. Change or disable each shortcut below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture-shortcut-defaults-copy")

                ForEach([RedaktrCaptureMode.area, .window, .screen]) { mode in
                    Picker(mode.displayName, selection: captureShortcutBinding(for: mode)) {
                        ForEach(RedaktrCaptureShortcutChoice.allCases) { choice in
                            Text(choice.displayName).tag(choice.rawValue)
                        }
                    }
                    .accessibilityIdentifier("capture-shortcut-picker-\(mode.rawValue)")
                }

                Text(captureShortcutSummary)
                    .font(.caption)
                    .foregroundStyle(captureShortcutSettings.hasConflicts ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture-shortcut-summary")

                if !captureShortcutRegistrationStatus.isEmpty {
                    Text(captureShortcutRegistrationStatus)
                        .font(.caption)
                        .foregroundStyle(captureShortcutSettings.hasConflicts ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture-shortcut-registration-status")
                }
                    }
            }

                if selectedSettingsTab == .privacy {
                    Section("Portability") {
                SettingsSectionHelpButton(
                    title: "Portability",
                    help: "Export and import policy settings only. Images, OCR text, matched text, and history are never included."
                )

                HStack(spacing: 10) {
                    Button(action: exportSettings) {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("export-custom-settings-button")

                    Button(action: importSettings) {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("import-custom-settings-button")

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("custom-settings-status")
                }

                Text("Stored locally on this Mac. Export writes policy, terms, regexes, and allowlist only. History and source images are never included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-portability-boundary-copy")
                    }
                    .id(SettingsAnchor.top)
                }

                if selectedSettingsTab == .help {
                    Section("Help") {
                SettingsSectionHelpButton(
                    title: "Help",
                    help: "Open the Help Center for workflows, keyboard shortcuts, privacy boundaries, and troubleshooting."
                )

                HStack(spacing: 10) {
                    Button {
                        NotificationCenter.default.post(name: .redaktrShowHelpCenter, object: nil)
                    } label: {
                        Label("Help Center", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("open-help-center-button")

                    Button {
                        NotificationCenter.default.post(name: .redaktrShowOnboarding, object: nil)
                    } label: {
                        Label("Quick Start", systemImage: "play.circle")
                    }
                    .buttonStyle(.redaktr(.secondary))
                    .accessibilityIdentifier("quick-start-settings-button")
                }

                Text("Help covers Quick Start, finding states, detection limits, protection modes, privacy, and troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-help-summary")
                    }
                    .id(SettingsAnchor.top)

                    Section("Contact") {
                Text("Visit GitHub for documentation, feature suggestions, and private security reporting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-contact-summary")

                Link(destination: RedaktrProjectLinks.repository) {
                    Label("Open GitHub Repository", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.redaktr(.primary, minWidth: 128))
                .accessibilityIdentifier("settings-contact-repository-link")
                    }
                }

                if selectedSettingsTab == .privacy {
                    Section("Safe-Share History") {
                SettingsSectionHelpButton(
                    title: "Safe-Share History",
                    help: "History stores local metadata only: action, source type, counts, timestamp, policy summary when available, and optional output path."
                )

                if historyStore.records.isEmpty {
                    Text("No local history yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("safe-share-history-empty")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(historyStore.records.prefix(8)) { record in
                            SafeShareHistoryRow(record: record)
                        }
                    }
                    .accessibilityIdentifier("safe-share-history-list")
                }

                HStack {
                    Button(role: .destructive, action: clearSafeShareHistory) {
                        Label("Clear History", systemImage: "trash")
                    }
                    .buttonStyle(.redaktr(.destructive))
                    .disabled(historyStore.records.isEmpty)
                    .accessibilityIdentifier("clear-safe-share-history-button")

                    Text("Local metadata only: timestamp, source type, action, counts, policy source/preset when available, and optional cleaned-output path. No images, OCR text, matched sensitive text, clipboard image data, or cleaned exports. Clearing history preserves policies, source images, and exported files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("safe-share-history-boundary-copy")
                }
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                settingsTabBar
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider()
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .formStyle(.grouped)
        .padding(.vertical, 10)
        .onChange(of: customTermsText) { _, _ in
            notifyDetectionSettingsChanged()
        }
        .onChange(of: customRegexesText) { _, _ in
            notifyDetectionSettingsChanged()
        }
        .onChange(of: allowlistText) { _, _ in
            notifyDetectionSettingsChanged()
        }
        .onChange(of: policyPresetID) { _, _ in
            notifyDetectionSettingsChanged()
        }
        .onChange(of: clipboardReplacementModeID) { _, _ in
            notifyClipboardProtectionSettingsChanged()
        }
        .onChange(of: selectedSettingsTab) { _, _ in
            focusedEditor = nil
            historyStore = SafeShareHistorySettingsStorage.store
            resetScrollPosition(proxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: .redaktrCustomDetectionSettingsRescanCompleted)) { _ in
            detectionSettingsStatusText = "Saved - current image re-scanned."
        }
        .onReceive(NotificationCenter.default.publisher(for: .redaktrOpenDetectionSettings)) { _ in
            selectedSettingsTab = .detection
            resetScrollPosition(proxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focusedEditor = nil
            resetScrollPosition(proxy)
        }
        .onAppear {
            focusedEditor = nil
            historyStore = SafeShareHistorySettingsStorage.store
            if isScreenshotWatchEnabled, !screenshotWatchFolderPath.isEmpty {
                refreshScreenshotWatchNotificationReadiness()
            }
            resetScrollPosition(proxy)
        }
            }
        }
        .frame(width: 600)
        .frame(minHeight: 620)
        .accessibilityIdentifier("custom-settings-view")
    }

    private var settingsTabBar: some View {
        Picker("Settings section", selection: $selectedSettingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
                    .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .accessibilityIdentifier("settings-tab-picker")
    }

    private func resetScrollPosition(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(SettingsAnchor.top, anchor: .top)
        }
    }

    private func protectionStatusActionTitle(for rail: ScreenshotProtectionRail) -> String {
        switch rail {
        case .redaktrCapture:
            return "Configure capture"
        case .folderWatch:
            return "Configure watch"
        case .clipboardGuard:
            return "Configure clipboard"
        case .policy:
            return "Configure policy"
        }
    }

    private func openProtectionStatusTarget(_ rail: ScreenshotProtectionRail, proxy: ScrollViewProxy) {
        let targetTab: SettingsTab
        let targetAnchor: String

        switch rail {
        case .redaktrCapture:
            targetTab = .protection
            targetAnchor = SettingsAnchor.captureOutput
        case .folderWatch:
            targetTab = .protection
            targetAnchor = SettingsAnchor.folderWatch
        case .clipboardGuard:
            targetTab = .protection
            targetAnchor = SettingsAnchor.clipboardProtection
        case .policy:
            targetTab = .detection
            targetAnchor = SettingsAnchor.top
        }

        selectedSettingsTab = targetTab
        DispatchQueue.main.async {
            proxy.scrollTo(targetAnchor, anchor: .top)
        }
    }

    private func detectorCategoryDispositionBinding(for category: DetectorCategory) -> Binding<RedactionPolicyDisposition> {
        Binding(
            get: {
                detectorCategoryPreferences.disposition(for: category)
                    ?? defaultDisposition(for: category)
            },
            set: { disposition in
                var preferences = detectorCategoryPreferences
                preferences.setDisposition(disposition, for: category)
                let preferencesData = RedaktrSettingsStorage.detectorCategoryPreferencesData(preferences)
                detectorCategoryPreferencesData = preferencesData
                notifyDetectionSettingsChanged(detectorCategoryPreferencesData: preferencesData)
            }
        )
    }

    private func defaultDisposition(for category: DetectorCategory) -> RedactionPolicyDisposition {
        switch category {
        case .emails, .phones, .cards, .secrets, .visualCodes, .faces, .custom:
            return .autoRedact
        case .ipAddresses, .highEntropy, .customerAccount:
            return .needsReview
        }
    }

    private func captureShortcutBinding(for mode: RedaktrCaptureMode) -> Binding<String> {
        Binding(
            get: {
                captureShortcutSettings.choice(for: mode).rawValue
            },
            set: { rawValue in
                let choice = RedaktrCaptureShortcutChoice(rawValue: rawValue) ?? .disabled
                switch mode {
                case .area:
                    areaShortcutID = choice.rawValue
                case .window:
                    windowShortcutID = choice.rawValue
                case .screen:
                    screenShortcutID = choice.rawValue
                }
                notifyCaptureShortcutSettingsChanged()
            }
        )
    }

    private var screenshotWatchFolderSummary: String {
        guard !screenshotWatchFolderPath.isEmpty else {
            return "Choose Desktop, your Screenshots folder, or another folder to scan new images after they are written."
        }

        let state = isScreenshotWatchEnabled ? "Watching" : "Paused"
        let name = screenshotWatchFolderDisplayName.isEmpty ? screenshotWatchFolderPath : screenshotWatchFolderDisplayName
        return "\(state): \(name)"
    }

    private var buildTrustWarning: String? {
        #if DEBUG
        "Development builds can behave differently with macOS notifications and Gatekeeper."
        #else
        nil
        #endif
    }

    private var clipboardProtectionSummary: String {
        let mode = ClipboardProtectionReplacementMode(rawValue: clipboardReplacementModeID) ?? .pauseIfUnsure
        guard isClipboardProtectionEnabled else {
            return "Off. Clipboard images are not scanned unless you paste them into Redaktr."
        }

        return "Active: \(mode.displayName). \(mode.detail)"
    }

    private var captureOutputMode: RedaktrCaptureOutputMode {
        RedaktrCaptureOutputMode(rawValue: captureOutputModeID) ?? .reviewInRedaktr
    }

    private var captureOutputSafetyMode: RedaktrAutoCleanSafetyMode {
        if let mode = RedaktrAutoCleanSafetyMode(rawValue: captureOutputSafetyModeID) {
            return mode
        }
        return RedaktrAutoCleanSafetyMode.fromLegacyRequiresNoReviewFindings(captureOutputRequiresNoReviewFindings)
    }

    private var captureOutputSummary: String {
        let safetyCopy = captureOutputSafetyMode.detail
        switch captureOutputMode {
        case .reviewInRedaktr:
            return "Captures open in Redaktr for review before copy or export."
        case .copyCleanedPNG:
            return "Captures can copy a cleaned PNG after scanning. \(safetyCopy)"
        case .saveCleanedPNG:
            return "Captures can save a cleaned PNG after scanning. Choose a folder below. \(safetyCopy)"
        case .saveAndCopyCleanedPNG:
            return "Captures can save and copy a cleaned PNG after scanning. Choose a folder below. \(safetyCopy)"
        }
    }

    private var captureOutputFolderSummary: String {
        if captureOutputFolderPath.isEmpty {
            return "No auto-save folder selected. Save modes fall back to review until a folder is chosen."
        }

        let name = captureOutputFolderDisplayName.isEmpty ? captureOutputFolderPath : captureOutputFolderDisplayName
        return "Auto-save folder: \(name)"
    }

    private var captureShortcutSummary: String {
        if captureShortcutSettings.hasConflicts {
            let duplicates = captureShortcutSettings.conflictingChoices
                .map(\.displayName)
                .sorted()
                .joined(separator: ", ")
            return "Duplicate shortcut: \(duplicates). Pick a unique shortcut for each enabled capture mode."
        }

        return "Defaults are Option-Shift-1 for area, Option-Shift-2 for window, and Option-Shift-3 for screen. Menu bar capture remains available if shortcuts are disabled."
    }

    private func notifyDetectionSettingsChanged(detectorCategoryPreferencesData preferencesData: Data? = nil) {
        detectionSettingsStatusText = "Saved locally. Current image re-scans automatically when open."
        NotificationCenter.default.post(
            name: .redaktrCustomDetectionSettingsDidChange,
            object: nil,
            userInfo: [
                RedaktrSettingsStorage.customTermsKey: customTermsText,
                RedaktrSettingsStorage.customRegexesKey: customRegexesText,
                RedaktrSettingsStorage.allowlistKey: allowlistText,
                RedaktrSettingsStorage.policyPresetKey: policyPresetID,
                RedaktrSettingsStorage.detectorCategoryPreferencesKey: preferencesData ?? detectorCategoryPreferencesData
            ]
        )
    }

    private func notifyScreenshotWatchSettingsChanged() {
        NotificationCenter.default.post(name: .redaktrScreenshotWatchSettingsDidChange, object: nil)
    }

    private func notifyClipboardProtectionSettingsChanged() {
        NotificationCenter.default.post(name: .redaktrClipboardProtectionSettingsDidChange, object: nil)
    }

    private func notifyCaptureShortcutSettingsChanged() {
        if captureShortcutSettings.hasConflicts {
            captureShortcutRegistrationStatus = "Resolve duplicate shortcuts before Redaktr can register them globally."
        } else {
            captureShortcutRegistrationStatus = "Shortcut settings saved."
        }
        NotificationCenter.default.post(name: .redaktrCaptureShortcutSettingsDidChange, object: nil)
    }

    private func setScreenshotWatchEnabled(_ isEnabled: Bool) {
        guard !screenshotWatchFolderPath.isEmpty else {
            isScreenshotWatchEnabled = false
            screenshotWatchStatusText = "Choose a folder before enabling watch."
            return
        }

        isScreenshotWatchEnabled = isEnabled
        screenshotWatchStatusText = isEnabled
            ? "Screenshot watch enabled."
            : "Screenshot watch paused."
        showsNotificationSettingsRecovery = false
        if isEnabled {
            refreshScreenshotWatchNotificationReadiness()
        }
        notifyScreenshotWatchSettingsChanged()
    }

    private func refreshScreenshotWatchNotificationReadiness() {
        ScreenshotWatchRiskNotifier.prepareForFolderWatch { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    screenshotWatchStatusText = "Screenshot watch enabled. Redaktr will notify you when sensitive data is found."
                    showsNotificationSettingsRecovery = false
                case .denied:
                    screenshotWatchStatusText = "Screenshot watch enabled. Notifications are off, so check Watched alerts in Redaktr or open macOS Notification Settings."
                    showsNotificationSettingsRecovery = true
                case .notDetermined:
                    screenshotWatchStatusText = "Screenshot watch enabled. Notification permission has not been decided yet."
                    showsNotificationSettingsRecovery = true
                @unknown default:
                    screenshotWatchStatusText = "Screenshot watch enabled. Check macOS notification settings if alerts do not appear."
                    showsNotificationSettingsRecovery = true
                }
            }
        }
    }

    private func watchDesktopFolder() {
        chooseScreenshotWatchFolder(
            title: "Watch Desktop",
            message: "Choose Desktop to let Redaktr scan new screenshots after they are saved there.",
            prompt: "Watch Desktop",
            defaultURL: ScreenshotWatchSettingsStorage.desktopURL
        )
    }

    private func watchScreenshotsFolder() {
        chooseScreenshotWatchFolder(
            title: "Watch Screenshots Folder",
            message: "Choose the folder where macOS saves screenshots so Redaktr can scan new image files after capture.",
            prompt: "Watch Screenshots",
            defaultURL: ScreenshotWatchSettingsStorage.screenshotsURL
        )
    }

    private func chooseScreenshotWatchFolder() {
        chooseScreenshotWatchFolder(
            title: "Choose Folder to Watch",
            message: "Choose one folder. Redaktr will scan new supported image files after they are fully written.",
            prompt: "Watch Folder",
            defaultURL: ScreenshotWatchSettingsStorage.screenshotsURL
        )
    }

    private func chooseScreenshotWatchFolder(
        title: String,
        message: String,
        prompt: String,
        defaultURL: URL?
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultURL

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ScreenshotWatchSettingsStorage.saveFolder(url)
            screenshotWatchStatusText = "Watching \(url.lastPathComponent)."
            refreshScreenshotWatchNotificationReadiness()
            notifyScreenshotWatchSettingsChanged()
        } catch {
            screenshotWatchStatusText = "Could not save folder access. Choose the folder again."
        }
    }

    private func stopWatchingScreenshots() {
        ScreenshotWatchSettingsStorage.clearFolder()
        screenshotWatchStatusText = "Screenshot watch stopped."
        notifyScreenshotWatchSettingsChanged()
    }

    private func setClipboardProtectionEnabled(_ isEnabled: Bool) {
        isClipboardProtectionEnabled = isEnabled
        clipboardProtectionStatusText = isEnabled
            ? "Clipboard image protection enabled."
            : "Clipboard image protection stopped."
        notifyClipboardProtectionSettingsChanged()
    }

    private func chooseCaptureOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Capture Output Folder"
        panel.message = "Choose where Redaktr saves cleaned PNGs from capture auto-output modes."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !captureOutputFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: captureOutputFolderPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try RedaktrCaptureOutputSettingsStorage.saveFolder(url)
            statusText = "Capture output folder saved."
        } catch {
            statusText = "Could not save capture output folder access. Choose the folder again."
        }
    }

    private func clearCaptureOutputFolder() {
        RedaktrCaptureOutputSettingsStorage.clearFolder()
        statusText = "Capture output folder cleared."
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.redaktrPolicyContentType, .json]
        panel.nameFieldStringValue = "Redaktr.redaktrpolicy"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                RedaktrPortableSettings(
                    appVersion: RedaktrProjectLinks.appVersionString,
                    source: policySource,
                    lock: policyLock,
                    customConfiguration: configuration,
                    policyPresetID: RedactionPolicyPresetID(rawValue: policyPresetID)
                )
            )
            try data.write(to: url, options: [.atomic])
            statusText = "Exported."
        } catch {
            statusText = "Export failed."
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.redaktrPolicyContentType, .json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let importedSettings: RedaktrPortableSettings
            if let portable = try? JSONDecoder().decode(RedaktrPortableSettings.self, from: data) {
                importedSettings = portable
            } else {
                let legacyConfiguration = try JSONDecoder().decode(CustomDetectionConfiguration.self, from: data)
                importedSettings = RedaktrPortableSettings(
                    customConfiguration: legacyConfiguration,
                    policyPresetID: Self.presetID(matching: legacyConfiguration.policyConfiguration)
                )
            }

            customTermsText = importedSettings.customConfiguration.terms.joined(separator: "\n")
            customRegexesText = importedSettings.customConfiguration.regexes.joined(separator: "\n")
            allowlistText = importedSettings.customConfiguration.allowlist.joined(separator: "\n")
            detectorCategoryPreferencesData = RedaktrSettingsStorage.detectorCategoryPreferencesData(
                importedSettings.customConfiguration.detectorCategoryPreferences
            )
            policyPresetID = importedSettings.policyPresetID?.rawValue
                ?? Self.presetID(matching: importedSettings.customConfiguration.policyConfiguration)?.rawValue
                ?? ""
            policySourceID = importedSettings.source == .managed ? PolicySource.managed.rawValue : PolicySource.imported.rawValue
            savePolicyLock(importedSettings.lock)
            statusText = "Imported."
            notifyDetectionSettingsChanged()
        } catch {
            statusText = "Import failed."
        }
    }

    private func clearSafeShareHistory() {
        SafeShareHistorySettingsStorage.clear()
        historyStore = SafeShareHistoryStore()
    }

    private static func presetID(matching configuration: RedactionPolicyConfiguration) -> RedactionPolicyPresetID? {
        RedactionPolicyCatalog.presets.first { preset in
            RedactionPolicyConfiguration(preset: preset.id) == configuration
        }?.id
    }

    private func savePolicyLock(_ lock: PolicyLock) {
        guard let data = try? JSONEncoder().encode(lock) else {
            policyLockData = Data()
            return
        }
        policyLockData = data
    }

    private static var redaktrPolicyContentType: UTType {
        UTType(filenameExtension: "redaktrpolicy") ?? .json
    }
}

private struct ScreenshotProtectionStatusRow: View {
    let item: ScreenshotProtectionStatusItem
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.rail.displayName)
                        .font(.callout.weight(.semibold))

                    Text(item.readiness.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.14), in: Capsule())
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .buttonStyle(.redaktr(.quiet, minWidth: 132))
                .accessibilityIdentifier("protection-status-action-\(item.rail.rawValue)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RedaktrUI.cardSurface, in: RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection-status-\(item.rail.rawValue)")
    }

    private var systemImage: String {
        switch item.readiness {
        case .on:
            return "checkmark.shield"
        case .off:
            return "pause.circle"
        case .needsSetup:
            return "wrench.and.screwdriver"
        case .needsPermission:
            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch item.readiness {
        case .on:
            return .green
        case .off:
            return .secondary
        case .needsSetup, .needsPermission:
            return .orange
        }
    }
}

private struct SafeShareHistoryRow: View {
    let record: SafeShareHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(record.action.displayName)
                    .font(.caption.weight(.semibold))
                Text(record.sourceType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.timestampFormatter.string(from: record.occurredAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(historyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(RedaktrUI.cardSurface, in: RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var historyDetail: String {
        var parts = [
            "\(record.totalFindings) findings",
            record.findingsSummary
        ]
        if let batchItemCount = record.batchItemCount, batchItemCount > 1 {
            parts.append("\(batchItemCount) images")
        }
        if let policySummary = record.policySummary, !policySummary.isEmpty {
            parts.append(policySummary)
        }
        if let outputPath = record.outputPath, !outputPath.isEmpty {
            parts.append(outputPath)
        }
        return parts.joined(separator: " - ")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum SettingsEditor: Hashable {
    case customTerms
    case customRegexes
    case allowlist
}

private struct DetectorCategoryDispositionControl: View {
    let category: DetectorCategory
    @Binding var selection: RedactionPolicyDisposition

    var body: some View {
        Picker("Disposition", selection: $selection) {
            ForEach(RedactionPolicyDisposition.allCases, id: \.rawValue) { disposition in
                Text(disposition.displayName)
                    .tag(disposition)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 220)
        .help(selection.summary)
        .accessibilityIdentifier("detector-category-disposition-\(category.rawValue)")
        .accessibilityValue(selection.displayName)
    }
}

private struct SettingsTextEditor: View {
    let title: String
    @Binding var text: String
    let focusedEditor: FocusState<SettingsEditor?>.Binding
    let editor: SettingsEditor
    let accessibilityIdentifier: String
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 88)
                .focused(focusedEditor, equals: editor)
                .accessibilityIdentifier("\(accessibilityIdentifier)-input")
                .disabled(isDisabled)
                .overlay(
                    RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius)
                        .stroke(Color.secondary.opacity(0.25))
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SettingsSectionHelpButton: View {
    let title: String
    let help: String

    var body: some View {
        HStack {
            Spacer()

            Button {
                NotificationCenter.default.post(name: .redaktrShowHelpCenter, object: nil)
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(RedaktrUI.controlSurface.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel("\(title) help")
            .accessibilityHint(help)
            .accessibilityIdentifier("settings-help-\(Self.identifier(from: title))")
        }
    }

    private static func identifier(from title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}
