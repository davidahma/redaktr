import Foundation

public enum ScreenshotProtectionRail: String, CaseIterable, Identifiable, Sendable {
    case redaktrCapture
    case folderWatch
    case clipboardGuard
    case policy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .redaktrCapture:
            return "Redaktr Capture"
        case .folderWatch:
            return "Folder Watch"
        case .clipboardGuard:
            return "Clipboard Guard"
        case .policy:
            return "Policy"
        }
    }
}

public enum ScreenshotProtectionReadiness: String, Sendable {
    case on
    case off
    case needsSetup
    case needsPermission

    public var displayName: String {
        switch self {
        case .on:
            return "On"
        case .off:
            return "Off"
        case .needsSetup:
            return "Needs setup"
        case .needsPermission:
            return "Needs permission"
        }
    }
}

public struct ScreenshotProtectionStatusInput: Equatable, Sendable {
    public var captureOutputMode: RedaktrCaptureOutputMode
    public var captureSaveFolderSelected: Bool
    public var captureShortcutsEnabled: Bool
    public var captureNeedsPermission: Bool
    public var folderWatchEnabled: Bool
    public var folderWatchFolderSelected: Bool
    public var clipboardGuardEnabled: Bool
    public var policyDisplayName: String
    public var isPolicyManaged: Bool

    public init(
        captureOutputMode: RedaktrCaptureOutputMode,
        captureSaveFolderSelected: Bool,
        captureShortcutsEnabled: Bool,
        captureNeedsPermission: Bool = false,
        folderWatchEnabled: Bool,
        folderWatchFolderSelected: Bool,
        clipboardGuardEnabled: Bool,
        policyDisplayName: String,
        isPolicyManaged: Bool
    ) {
        self.captureOutputMode = captureOutputMode
        self.captureSaveFolderSelected = captureSaveFolderSelected
        self.captureShortcutsEnabled = captureShortcutsEnabled
        self.captureNeedsPermission = captureNeedsPermission
        self.folderWatchEnabled = folderWatchEnabled
        self.folderWatchFolderSelected = folderWatchFolderSelected
        self.clipboardGuardEnabled = clipboardGuardEnabled
        self.policyDisplayName = policyDisplayName
        self.isPolicyManaged = isPolicyManaged
    }
}

public struct ScreenshotProtectionStatusItem: Equatable, Identifiable, Sendable {
    public var rail: ScreenshotProtectionRail
    public var readiness: ScreenshotProtectionReadiness
    public var detail: String

    public var id: String { rail.rawValue }

    public init(
        rail: ScreenshotProtectionRail,
        readiness: ScreenshotProtectionReadiness,
        detail: String
    ) {
        self.rail = rail
        self.readiness = readiness
        self.detail = detail
    }
}

public enum ScreenshotProtectionStatusBuilder {
    public static func build(
        input: ScreenshotProtectionStatusInput
    ) -> [ScreenshotProtectionStatusItem] {
        [
            captureStatus(input: input),
            folderWatchStatus(input: input),
            clipboardGuardStatus(input: input),
            policyStatus(input: input)
        ]
    }

    private static func captureStatus(
        input: ScreenshotProtectionStatusInput
    ) -> ScreenshotProtectionStatusItem {
        if input.captureNeedsPermission {
            return ScreenshotProtectionStatusItem(
                rail: .redaktrCapture,
                readiness: .needsPermission,
                detail: "Allow Screen Recording in macOS Privacy settings before using capture shortcuts."
            )
        }

        if input.captureOutputMode.savesToFolder, !input.captureSaveFolderSelected {
            return ScreenshotProtectionStatusItem(
                rail: .redaktrCapture,
                readiness: .needsSetup,
                detail: "Choose an auto-save folder or switch capture output back to review."
            )
        }

        let shortcutDetail = input.captureShortcutsEnabled
            ? "Global shortcuts are configured."
            : "Menu bar capture is still available; shortcuts are disabled."
        return ScreenshotProtectionStatusItem(
            rail: .redaktrCapture,
            readiness: .on,
            detail: "\(input.captureOutputMode.displayName). \(shortcutDetail)"
        )
    }

    private static func folderWatchStatus(
        input: ScreenshotProtectionStatusInput
    ) -> ScreenshotProtectionStatusItem {
        if input.folderWatchEnabled, input.folderWatchFolderSelected {
            return ScreenshotProtectionStatusItem(
                rail: .folderWatch,
                readiness: .on,
                detail: "Scans new screenshots after they are saved in the watched folder."
            )
        }

        if input.folderWatchEnabled, !input.folderWatchFolderSelected {
            return ScreenshotProtectionStatusItem(
                rail: .folderWatch,
                readiness: .needsSetup,
                detail: "Choose Desktop, Screenshots, or another folder before watch can run."
            )
        }

        if input.folderWatchFolderSelected {
            return ScreenshotProtectionStatusItem(
                rail: .folderWatch,
                readiness: .off,
                detail: "Folder selected, but watch is paused."
            )
        }

        return ScreenshotProtectionStatusItem(
            rail: .folderWatch,
            readiness: .off,
            detail: "No watched folder selected."
        )
    }

    private static func clipboardGuardStatus(
        input: ScreenshotProtectionStatusInput
    ) -> ScreenshotProtectionStatusItem {
        ScreenshotProtectionStatusItem(
            rail: .clipboardGuard,
            readiness: input.clipboardGuardEnabled ? .on : .off,
            detail: input.clipboardGuardEnabled
                ? "Scans image clipboard changes locally before risky screenshots are pasted elsewhere."
                : "Paste images manually or turn on Clipboard Guard for AI chat, Slack, email, and tickets."
        )
    }

    private static func policyStatus(
        input: ScreenshotProtectionStatusInput
    ) -> ScreenshotProtectionStatusItem {
        let trimmedPolicyName = input.policyDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isPolicyManaged {
            return ScreenshotProtectionStatusItem(
                rail: .policy,
                readiness: .on,
                detail: "Managed by team policy."
            )
        }

        return ScreenshotProtectionStatusItem(
            rail: .policy,
            readiness: .on,
            detail: trimmedPolicyName.isEmpty
                ? "Current defaults. Add presets, terms, regexes, or imported .redaktrpolicy files when needed."
                : "Active preset: \(trimmedPolicyName)."
        )
    }
}
