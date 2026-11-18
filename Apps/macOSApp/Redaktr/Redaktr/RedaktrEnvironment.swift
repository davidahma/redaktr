import AppKit
import Foundation

enum RedaktrProjectLinks {
    static let repository = URL(string: "https://github.com/davidahma/redaktr")!

    static var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}

enum RedaktrUITestEnvironment {
    static let bundleID = "com.davidahma.redaktr.uitesting"

    static var isEnabled: Bool {
        #if DEBUG
        return Bundle.main.bundleIdentifier == bundleID &&
            ProcessInfo.processInfo.environment["REDAKTR_UI_TEST_MODE"] == "1"
        #else
        return false
        #endif
    }

    static func resetDefaultsIfRequested() {
        guard isEnabled, ProcessInfo.processInfo.environment["REDAKTR_UI_RESET_DEFAULTS"] == "1" else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }
}

@MainActor
enum RedaktrPasteboard {
    static var current: NSPasteboard {
        guard RedaktrUITestEnvironment.isEnabled else { return .general }
        if let name = ProcessInfo.processInfo.environment["REDAKTR_UI_TEST_PASTEBOARD"],
           name.hasPrefix(RedaktrUITestEnvironment.bundleID + ".") {
            return NSPasteboard(name: .init(name))
        }
        return NSPasteboard(name: .init(RedaktrUITestEnvironment.bundleID + ".default"))
    }
}
