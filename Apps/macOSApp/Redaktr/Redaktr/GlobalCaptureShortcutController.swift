import Carbon.HIToolbox
import Foundation
import RedaktrCore

final class GlobalCaptureShortcutController: ObservableObject {
    private static weak var activeController: GlobalCaptureShortcutController?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var onShortcut: ((RedaktrCaptureMode) -> Void)?

    func start(onShortcut: @escaping (RedaktrCaptureMode) -> Void) {
        self.onShortcut = onShortcut
        Self.activeController = self
        installEventHandlerIfNeeded()
        refreshRegistration()
    }

    func stop() {
        unregisterHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    func refreshRegistration() {
        unregisterHotKeys()

        let settings = RedaktrCaptureShortcutSettingsStorage.settings
        guard !settings.hasConflicts else {
            RedaktrCaptureShortcutSettingsStorage.setRegistrationStatus(
                "Resolve duplicate capture shortcuts before Redaktr can register them globally."
            )
            return
        }

        #if DEBUG
        if RedaktrUITestEnvironment.isEnabled,
           ProcessInfo.processInfo.environment["REDAKTR_UI_ENABLE_GLOBAL_CAPTURE_SHORTCUTS"] != "1" {
            RedaktrCaptureShortcutSettingsStorage.setRegistrationStatus("Shortcut registration skipped during UI tests.")
            return
        }
        #endif

        var failures = [String]()
        for (mode, choice) in settings.enabledShortcuts {
            guard let keyCode = choice.keyCode else { continue }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: redaktrHotKeySignature,
                id: mode.hotKeyIdentifier
            )
            let status = RegisterEventHotKey(
                keyCode,
                carbonModifierFlags(for: choice),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            } else {
                failures.append("\(mode.displayName): \(choice.displayName)")
            }
        }

        if failures.isEmpty {
            RedaktrCaptureShortcutSettingsStorage.setRegistrationStatus("Capture shortcuts are active.")
        } else {
            RedaktrCaptureShortcutSettingsStorage.setRegistrationStatus(
                "Could not register \(failures.joined(separator: ", ")). Choose another shortcut or use the menu bar fallback."
            )
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, hotKeyID.signature == redaktrHotKeySignature else {
                return noErr
            }

            let mode = RedaktrCaptureMode.mode(forHotKeyIdentifier: hotKeyID.id)
            DispatchQueue.main.async {
                guard let mode else { return }
                GlobalCaptureShortcutController.activeController?.onShortcut?(mode)
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )

        if status == noErr {
            eventHandler = handlerRef
        } else {
            RedaktrCaptureShortcutSettingsStorage.setRegistrationStatus(
                "Could not install the shortcut listener. Use the menu bar capture actions."
            )
        }
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    private func carbonModifierFlags(for choice: RedaktrCaptureShortcutChoice) -> UInt32 {
        choice.modifierIDs.reduce(UInt32(0)) { flags, modifier in
            switch modifier {
            case .control:
                return flags | UInt32(controlKey)
            case .option:
                return flags | UInt32(optionKey)
            case .shift:
                return flags | UInt32(shiftKey)
            }
        }
    }
}

private let redaktrHotKeySignature: OSType = 0x52444B54
