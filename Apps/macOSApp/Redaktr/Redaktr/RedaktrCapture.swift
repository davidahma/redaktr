import AppKit
import CoreGraphics
import Foundation
import RedaktrCore

enum RedaktrCaptureShortcutSettingsStorage {
    static let areaKey = RedaktrCaptureShortcutStorageKey.area.rawValue
    static let windowKey = RedaktrCaptureShortcutStorageKey.window.rawValue
    static let screenKey = RedaktrCaptureShortcutStorageKey.screen.rawValue
    static let registrationStatusKey = RedaktrCaptureShortcutStorageKey.registrationStatus.rawValue

    static let defaultAreaID = RedaktrCaptureMode.area.defaultShortcutChoice.rawValue
    static let defaultWindowID = RedaktrCaptureMode.window.defaultShortcutChoice.rawValue
    static let defaultScreenID = RedaktrCaptureMode.screen.defaultShortcutChoice.rawValue

    static var settings: RedaktrCaptureShortcutSettings {
        let defaults = UserDefaults.standard
        return RedaktrCaptureShortcutSettings(
            rawAreaID: defaults.string(forKey: areaKey),
            rawWindowID: defaults.string(forKey: windowKey),
            rawScreenID: defaults.string(forKey: screenKey)
        )
    }

    static func choice(for mode: RedaktrCaptureMode) -> RedaktrCaptureShortcutChoice {
        settings.choice(for: mode)
    }

    static func settings(
        areaID: String,
        windowID: String,
        screenID: String
    ) -> RedaktrCaptureShortcutSettings {
        RedaktrCaptureShortcutSettings(
            rawAreaID: areaID,
            rawWindowID: windowID,
            rawScreenID: screenID
        )
    }

    static func setRegistrationStatus(_ status: String) {
        UserDefaults.standard.set(status, forKey: registrationStatusKey)
    }
}

enum RedaktrCaptureError: LocalizedError {
    case captureToolUnavailable
    case permissionDenied
    case canceled
    case outputMissing
    case failed

    var errorDescription: String? {
        switch self {
        case .captureToolUnavailable:
            return "The macOS capture tool is unavailable."
        case .permissionDenied:
            return "Screen capture permission is not enabled for Redaktr."
        case .canceled:
            return "Capture was canceled."
        case .outputMissing:
            return "No capture image was created."
        case .failed:
            return "Capture failed."
        }
    }
}

struct RedaktrScreenCaptureService {
    private let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    func capture(_ mode: RedaktrCaptureMode) async throws -> URL {
        #if DEBUG
        if RedaktrUITestEnvironment.isEnabled,
           let fixturePath = ProcessInfo.processInfo.environment["REDAKTR_UI_CAPTURE_FIXTURE_PATH"],
           !fixturePath.isEmpty {
            let outputURL = temporaryOutputURL(for: mode)
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: fixturePath), to: outputURL)
            return outputURL
        }
        #endif

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RedaktrCaptureError.captureToolUnavailable
        }

        guard await requestScreenCaptureAccessIfNeeded() else {
            throw RedaktrCaptureError.permissionDenied
        }

        let outputURL = temporaryOutputURL(for: mode)
        try? FileManager.default.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = mode.screencaptureArguments + [outputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { terminatedProcess in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard terminatedProcess.terminationStatus == 0 else {
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        continuation.resume(throwing: RedaktrCaptureError.canceled)
                        return
                    }

                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: RedaktrCaptureError.outputMissing)
                        return
                    }

                    continuation.resume(returning: ())
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: RedaktrCaptureError.failed)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        return outputURL
    }

    private func requestScreenCaptureAccessIfNeeded() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    private func temporaryOutputURL(for mode: RedaktrCaptureMode) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("redaktr-capture-\(mode.rawValue)-\(UUID().uuidString)")
            .appendingPathExtension("png")
    }
}

private extension RedaktrCaptureMode {
    var screencaptureArguments: [String] {
        switch self {
        case .screen:
            return ["-x", "-t", "png"]
        case .window:
            return ["-i", "-w", "-x", "-t", "png"]
        case .area:
            return ["-i", "-s", "-x", "-t", "png"]
        }
    }
}
