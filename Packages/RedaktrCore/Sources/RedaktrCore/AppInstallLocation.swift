import Foundation

public enum AppInstallLocation {
    public static let dismissedPreferenceKey = "redaktrMoveToApplicationsDismissedV2"

    public static func shouldPromptToMove(
        appBundlePath: String,
        homeDirectoryPath: String,
        hasDismissedPrompt: Bool,
        isUITestMode: Bool,
        allowsUITestOverride: Bool = false
    ) -> Bool {
        if hasDismissedPrompt { return false }
        if isUITestMode && !allowsUITestOverride { return false }
        return !isInstalledLocation(appBundlePath: appBundlePath, homeDirectoryPath: homeDirectoryPath)
    }

    public static func isInstalledLocation(appBundlePath: String, homeDirectoryPath: String) -> Bool {
        let standardizedAppPath = standardizedPath(appBundlePath)
        let standardizedHomePath = standardizedPath(homeDirectoryPath)

        if isPath(standardizedAppPath, inside: "/Applications")
            || isPath(standardizedAppPath, inside: "/System/Volumes/Data/Applications")
        {
            return true
        }

        let userApplicationsPath = standardizedPath(
            URL(fileURLWithPath: standardizedHomePath, isDirectory: true)
                .appendingPathComponent("Applications", isDirectory: true)
                .path
        )
        if isPath(standardizedAppPath, inside: userApplicationsPath) {
            return true
        }

        return false
    }

    public static func isLikelyTranslocated(appBundlePath: String) -> Bool {
        standardizedPath(appBundlePath).contains("/AppTranslocation/")
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isPath(_ path: String, inside directoryPath: String) -> Bool {
        let standardizedDirectoryPath = standardizedPath(directoryPath)
        return path == standardizedDirectoryPath || path.hasPrefix(standardizedDirectoryPath + "/")
    }
}
