import AppKit
import Darwin
import Foundation
import RedaktrCore
import SwiftUI
import UserNotifications

enum ScreenshotWatchSettingsStorage {
    static let isEnabledKey = "screenshotWatchEnabled"
    static let folderBookmarkKey = "screenshotWatchFolderBookmark"
    static let folderDisplayNameKey = "screenshotWatchFolderDisplayName"
    static let folderPathKey = "screenshotWatchFolderPath"

    static var desktopURL: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    static var screenshotsURL: URL? {
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let screenshotsURL = picturesURL?.appendingPathComponent("Screenshots", isDirectory: true)
        if let screenshotsURL, FileManager.default.fileExists(atPath: screenshotsURL.path) {
            return screenshotsURL
        }

        return desktopURL
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
        UserDefaults.standard.set(true, forKey: isEnabledKey)
    }

    static func clearFolder() {
        UserDefaults.standard.set(false, forKey: isEnabledKey)
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: folderPathKey)
    }

    static func resolveFolder() throws -> ResolvedScreenshotWatchFolder? {
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

        return ResolvedScreenshotWatchFolder(url: url, isStale: isStale)
    }
}

struct ResolvedScreenshotWatchFolder {
    let url: URL
    let isStale: Bool
}

@MainActor
final class ScreenshotWatchController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var runtimeStatus = "Screenshot watch is off."

    private let watcher = ScreenshotFolderWatcher()
    private var activeSecurityScopedURL: URL?
    private var didStartSecurityScope = false
    private var candidateHandler: (([URL]) -> Void)?

    init() {
        watcher.onReadyCandidates = { [weak self] urls in
            self?.candidateHandler?(urls)
        }
        watcher.onError = { [weak self] error in
            self?.isRunning = false
            self?.runtimeStatus = error.localizedDescription
        }
    }

    func refreshFromStoredSettings(
        isUITestMode: Bool,
        onCandidates: @escaping ([URL]) -> Void
    ) {
        candidateHandler = onCandidates
        stop()

        guard UserDefaults.standard.bool(forKey: ScreenshotWatchSettingsStorage.isEnabledKey) else {
            runtimeStatus = "Screenshot watch is off."
            return
        }

        if isUITestMode && ProcessInfo.processInfo.environment["REDAKTR_UI_ENABLE_SCREENSHOT_WATCH"] != "1" {
            runtimeStatus = "Screenshot watch disabled during UI tests."
            return
        }

        do {
            guard let folder = try ScreenshotWatchSettingsStorage.resolveFolder() else {
                runtimeStatus = "Choose a folder to enable screenshot watch."
                return
            }

            let didAccess = folder.url.startAccessingSecurityScopedResource()
            activeSecurityScopedURL = folder.url
            didStartSecurityScope = didAccess

            if folder.isStale {
                try ScreenshotWatchSettingsStorage.saveFolder(folder.url)
            }

            try watcher.start(watching: folder.url)
            isRunning = true
            runtimeStatus = "Watching \(folder.url.lastPathComponent) for new screenshots."
        } catch {
            stop()
            runtimeStatus = "Screenshot watch could not start. Choose the folder again."
        }
    }

    func stop() {
        watcher.stop()
        isRunning = false
        if didStartSecurityScope {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURL = nil
        didStartSecurityScope = false
    }
}

@MainActor
final class ScreenshotFolderWatcher {
    var onReadyCandidates: (([URL]) -> Void)?
    var onError: ((Error) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var directoryURL: URL?
    private var plan = ScreenshotFolderWatchPlan()
    private var settleTask: Task<Void, Never>?

    deinit {
        source?.cancel()
        settleTask?.cancel()
    }

    func start(watching url: URL) throws {
        stop()

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw ScreenshotFolderWatcherError.cannotOpenFolder
        }

        directoryURL = url
        plan = ScreenshotFolderWatchPlan(settleInterval: 1.0)
        plan.seedKnownFiles(ScreenshotFolderWatchSnapshot.candidates(in: url))

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            Task { @MainActor in
                self?.handleDirectoryEvent(event)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        settleTask?.cancel()
        settleTask = nil
        source?.cancel()
        source = nil
        directoryURL = nil
        plan = ScreenshotFolderWatchPlan()
    }

    private func handleDirectoryEvent(_ event: DispatchSource.FileSystemEvent) {
        guard let directoryURL else { return }

        if event.contains(.delete) || event.contains(.rename) {
            onError?(ScreenshotFolderWatcherError.folderMovedOrDeleted)
            stop()
            return
        }

        let candidates = ScreenshotFolderWatchSnapshot.candidates(in: directoryURL)
        plan.observe(candidates, at: Date())
        scheduleReadyCandidateDelivery()
    }

    private func scheduleReadyCandidateDelivery() {
        settleTask?.cancel()
        let nanoseconds = UInt64(max(plan.settleInterval, 0.1) * 1_000_000_000)

        settleTask = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            deliverReadyCandidates()
        }
    }

    private func deliverReadyCandidates() {
        guard let directoryURL else { return }

        let candidates = ScreenshotFolderWatchSnapshot.candidates(in: directoryURL)
        let readyCandidates = plan.readyCandidates(afterObserving: candidates, at: Date())
        guard !readyCandidates.isEmpty else { return }

        onReadyCandidates?(readyCandidates.map(\.url))
    }
}

private enum ScreenshotFolderWatcherError: LocalizedError {
    case cannotOpenFolder
    case folderMovedOrDeleted

    var errorDescription: String? {
        switch self {
        case .cannotOpenFolder:
            return "Screenshot watch could not open the selected folder."
        case .folderMovedOrDeleted:
            return "Screenshot watch stopped because the selected folder moved or was deleted."
        }
    }
}

enum ScreenshotWatchRiskNotifier {
    fileprivate static let categoryIdentifier = "redaktr-screenshot-watch-risk"
    fileprivate static let reviewActionIdentifier = "redaktr-review-watched-screenshot"

    static func configureNotificationHandling() {
        let center = UNUserNotificationCenter.current()
        center.delegate = ScreenshotWatchNotificationDelegate.shared

        let reviewAction = UNNotificationAction(
            identifier: reviewActionIdentifier,
            title: "Review in Redaktr",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [reviewAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    static func prepareForFolderWatch(completion: ((UNAuthorizationStatus) -> Void)? = nil) {
        if let overrideStatus = uiTestAuthorizationStatusOverride {
            completion?(overrideStatus)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { isGranted, _ in
                    completion?(isGranted ? .authorized : .denied)
                }
            default:
                completion?(settings.authorizationStatus)
            }
        }
    }

    private static var uiTestAuthorizationStatusOverride: UNAuthorizationStatus? {
        let environment = ProcessInfo.processInfo.environment
        guard RedaktrUITestEnvironment.isEnabled,
              let rawValue = environment["REDAKTR_UI_NOTIFICATION_AUTHORIZATION_STATUS"]
        else {
            return nil
        }

        switch rawValue {
        case "authorized":
            return .authorized
        case "denied":
            return .denied
        case "notDetermined":
            return .notDetermined
        case "provisional":
            return .provisional
        default:
            return nil
        }
    }

    static func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for value in urls {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func notify(fileName: String, findingCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                deliverNotification(fileName: fileName, findingCount: findingCount)
            } else if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { isGranted, _ in
                    guard isGranted else { return }
                    deliverNotification(fileName: fileName, findingCount: findingCount)
                }
            }
        }
    }

    static func notifyAutoCleanReceipt(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "redaktr-autoclean-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private static func deliverNotification(fileName: String, findingCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Sensitive data found in screenshot"
        content.body = "\(fileName) has \(findingCount) possible \(findingCount == 1 ? "leak" : "leaks"). Review in Redaktr before sharing."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let request = UNNotificationRequest(
            identifier: "redaktr-screenshot-watch-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

private final class ScreenshotWatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScreenshotWatchNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == ScreenshotWatchRiskNotifier.categoryIdentifier {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .redaktrOpenLatestWatchedScreenshot, object: nil)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
