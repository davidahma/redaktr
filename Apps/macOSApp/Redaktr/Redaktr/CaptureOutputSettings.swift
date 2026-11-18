import Foundation
import RedaktrCore

enum RedaktrCaptureOutputSettingsStorage {
    static let modeKey = "redaktrCaptureOutputMode"
    static let safetyModeKey = "redaktrCaptureOutputSafetyMode"
    static let requiresNoReviewFindingsKey = "redaktrCaptureOutputRequiresNoReviewFindings"
    static let folderBookmarkKey = "redaktrCaptureOutputFolderBookmark"
    static let folderDisplayNameKey = "redaktrCaptureOutputFolderDisplayName"
    static let folderPathKey = "redaktrCaptureOutputFolderPath"

    static var policy: RedaktrCaptureOutputPolicy {
        let defaults = UserDefaults.standard
        let mode = RedaktrCaptureOutputMode(rawValue: defaults.string(forKey: modeKey) ?? "")
            ?? .reviewInRedaktr
        let safetyMode: RedaktrAutoCleanSafetyMode
        if let rawSafetyMode = defaults.string(forKey: safetyModeKey),
           let storedSafetyMode = RedaktrAutoCleanSafetyMode(rawValue: rawSafetyMode) {
            safetyMode = storedSafetyMode
        } else if defaults.object(forKey: requiresNoReviewFindingsKey) == nil {
            safetyMode = .pauseIfUnsure
        } else {
            safetyMode = .fromLegacyRequiresNoReviewFindings(defaults.bool(forKey: requiresNoReviewFindingsKey))
        }

        return RedaktrCaptureOutputPolicy(
            mode: mode,
            safetyMode: safetyMode
        )
    }

    static func saveFolder(_ url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderDisplayNameKey)
        UserDefaults.standard.set(url.path, forKey: folderPathKey)
    }

    static func clearFolder() {
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: folderPathKey)
    }

    static func resolveFolder() throws -> ResolvedCaptureOutputFolder? {
        guard let bookmark = UserDefaults.standard.data(forKey: folderBookmarkKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedCaptureOutputFolder(url: url, isStale: isStale)
    }
}

struct ResolvedCaptureOutputFolder {
    let url: URL
    let isStale: Bool
}
