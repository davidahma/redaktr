import AppKit
import Foundation
import RedaktrCore
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardProtectionSettingsStorage {
    static let isEnabledKey = "clipboardProtectionEnabled"
    static let replacementModeKey = "clipboardProtectionReplacementMode"

    static var configuration: ClipboardProtectionConfiguration {
        ClipboardProtectionConfiguration(
            isEnabled: UserDefaults.standard.bool(forKey: isEnabledKey),
            replacementMode: replacementMode
        )
    }

    static var replacementMode: ClipboardProtectionReplacementMode {
        let rawValue = UserDefaults.standard.string(forKey: replacementModeKey) ?? ""
        return (ClipboardProtectionReplacementMode(rawValue: rawValue) ?? .pauseIfUnsure).normalizedReplacementMode
    }
}

struct ClipboardImageCandidate: Sendable {
    let data: Data
    let changeCount: Int
    let replacementMode: ClipboardProtectionReplacementMode
}

@MainActor
final class ClipboardProtectionController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var runtimeStatus = "Clipboard protection is off."

    private var monitorTask: Task<Void, Never>?
    private var monitorPlan = ClipboardProtectionMonitorPlan()
    private var onImageCandidate: ((ClipboardImageCandidate) -> Void)?

    func refreshFromStoredSettings(
        isUITestMode: Bool,
        onImageCandidate: @escaping (ClipboardImageCandidate) -> Void
    ) {
        self.onImageCandidate = onImageCandidate
        stop()

        let configuration = ClipboardProtectionSettingsStorage.configuration
        guard configuration.isEnabled else {
            runtimeStatus = "Clipboard protection is off."
            return
        }

        if isUITestMode && ProcessInfo.processInfo.environment["REDAKTR_UI_ENABLE_CLIPBOARD_PROTECTION"] != "1" {
            runtimeStatus = "Clipboard protection disabled during UI tests."
            return
        }

        isRunning = true
        runtimeStatus = "\(configuration.replacementMode.displayName) for clipboard images."
        startMonitoring(configuration: configuration)
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        monitorPlan = ClipboardProtectionMonitorPlan()
        isRunning = false
    }

    func markHandled(changeCount: Int) {
        monitorPlan.markHandled(changeCount: changeCount)
    }

    private func startMonitoring(configuration: ClipboardProtectionConfiguration) {
        let pasteboard = RedaktrPasteboard.current
        monitorPlan.markHandled(changeCount: pasteboard.changeCount)

        monitorTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 450_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                let currentPasteboard = RedaktrPasteboard.current
                let changeCount = currentPasteboard.changeCount
                let containsImage = ClipboardImageReader.containsImage(in: currentPasteboard)

                switch monitorPlan.observe(changeCount: changeCount, containsImage: containsImage, at: Date()) {
                case .scan:
                    guard let data = ClipboardImageReader.imageData(in: currentPasteboard) else {
                        monitorPlan.markHandled(changeCount: changeCount)
                        continue
                    }
                    onImageCandidate?(
                        ClipboardImageCandidate(
                            data: data,
                            changeCount: changeCount,
                            replacementMode: ClipboardProtectionSettingsStorage.replacementMode
                        )
                    )
                case .ignore, .wait:
                    break
                }
            }
        }
    }
}

enum ClipboardImageReader {
    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier)
    ]

    static func containsImage(in pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: imagePasteboardTypes) != nil {
            return true
        }

        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    static func imageData(in pasteboard: NSPasteboard) -> Data? {
        for type in imagePasteboardTypes {
            if let data = pasteboard.data(forType: type) {
                return data
            }
        }

        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        return images?.first?.tiffRepresentation
    }
}
