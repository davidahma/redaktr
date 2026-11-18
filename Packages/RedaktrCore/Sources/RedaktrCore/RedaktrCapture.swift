import Foundation

public enum RedaktrCaptureMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case screen
    case window
    case area

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .screen:
            return "Capture screen"
        case .window:
            return "Capture window"
        case .area:
            return "Capture area"
        }
    }

    public var commandTitle: String {
        switch self {
        case .screen:
            return "Capture Entire Screen"
        case .window:
            return "Capture Window..."
        case .area:
            return "Capture Area..."
        }
    }

    public var systemImage: String {
        switch self {
        case .screen:
            return "display"
        case .window:
            return "macwindow"
        case .area:
            return "rectangle.dashed"
        }
    }

    public var reviewSourceLabel: String {
        switch self {
        case .screen:
            return "Screen capture"
        case .window:
            return "Window capture"
        case .area:
            return "Area capture"
        }
    }

    public var startsInteractiveSelection: Bool {
        switch self {
        case .screen:
            return false
        case .window, .area:
            return true
        }
    }

    public var preparationMessage: String {
        switch self {
        case .screen:
            return "Capturing the screen locally. Redaktr may need macOS Screen Recording permission."
        case .window:
            return "Choose a window to capture. Redaktr will scan the temporary PNG locally."
        case .area:
            return "Drag to select an area. Redaktr will scan the temporary PNG locally."
        }
    }

    public static let permissionExplanation =
        "Redaktr uses macOS screen capture permission only to create a local temporary image for review. It does not intercept Apple's screenshot shortcuts or send captures to a server."

    public var hotKeyIdentifier: UInt32 {
        switch self {
        case .area:
            return 1
        case .window:
            return 2
        case .screen:
            return 3
        }
    }

    public static func mode(forHotKeyIdentifier identifier: UInt32) -> RedaktrCaptureMode? {
        switch identifier {
        case RedaktrCaptureMode.area.hotKeyIdentifier:
            return .area
        case RedaktrCaptureMode.window.hotKeyIdentifier:
            return .window
        case RedaktrCaptureMode.screen.hotKeyIdentifier:
            return .screen
        default:
            return nil
        }
    }

    public var defaultShortcutChoice: RedaktrCaptureShortcutChoice {
        RedaktrCaptureShortcutSettings.defaults.choice(for: self)
    }
}

public enum RedaktrCaptureShortcutStorageKey: String, CaseIterable, Sendable {
    case area = "redaktrCaptureShortcutArea"
    case window = "redaktrCaptureShortcutWindow"
    case screen = "redaktrCaptureShortcutScreen"
    case registrationStatus = "redaktrCaptureShortcutRegistrationStatus"

    public static func shortcutChoiceKey(for mode: RedaktrCaptureMode) -> RedaktrCaptureShortcutStorageKey {
        switch mode {
        case .area:
            return .area
        case .window:
            return .window
        case .screen:
            return .screen
        }
    }
}

public enum RedaktrCaptureShortcutChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case disabled
    case optionShift1
    case optionShift2
    case optionShift3
    case controlOption1
    case controlOption2
    case controlOption3

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .optionShift1: return "Option-Shift-1"
        case .optionShift2: return "Option-Shift-2"
        case .optionShift3: return "Option-Shift-3"
        case .controlOption1: return "Control-Option-1"
        case .controlOption2: return "Control-Option-2"
        case .controlOption3: return "Control-Option-3"
        }
    }

    public var keyEquivalent: String? {
        switch self {
        case .disabled:
            return nil
        case .optionShift1, .controlOption1:
            return "1"
        case .optionShift2, .controlOption2:
            return "2"
        case .optionShift3, .controlOption3:
            return "3"
        }
    }

    public var menuShortcutHint: String? {
        guard let keyEquivalent else { return nil }

        let modifierGlyphs = RedaktrCaptureShortcutModifier.menuDisplayOrder.compactMap { modifier in
            modifierIDs.contains(modifier) ? modifier.menuGlyph : nil
        }
        return modifierGlyphs.joined() + keyEquivalent
    }

    public var keyCode: UInt32? {
        switch self {
        case .disabled:
            return nil
        case .optionShift1, .controlOption1:
            return 18
        case .optionShift2, .controlOption2:
            return 19
        case .optionShift3, .controlOption3:
            return 20
        }
    }

    public var modifierIDs: Set<RedaktrCaptureShortcutModifier> {
        switch self {
        case .disabled:
            return []
        case .optionShift1, .optionShift2, .optionShift3:
            return [.option, .shift]
        case .controlOption1, .controlOption2, .controlOption3:
            return [.control, .option]
        }
    }

    public var isEnabled: Bool {
        self != .disabled
    }
}

public enum RedaktrCaptureShortcutModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift

    public static let menuDisplayOrder: [RedaktrCaptureShortcutModifier] = [
        .control,
        .option,
        .shift
    ]

    public var menuGlyph: String {
        switch self {
        case .control:
            return "⌃"
        case .option:
            return "⌥"
        case .shift:
            return "⇧"
        }
    }
}

public struct RedaktrCaptureShortcutSettings: Codable, Equatable, Sendable {
    public var area: RedaktrCaptureShortcutChoice
    public var window: RedaktrCaptureShortcutChoice
    public var screen: RedaktrCaptureShortcutChoice

    public init(
        area: RedaktrCaptureShortcutChoice = .optionShift1,
        window: RedaktrCaptureShortcutChoice = .optionShift2,
        screen: RedaktrCaptureShortcutChoice = .optionShift3
    ) {
        self.area = area
        self.window = window
        self.screen = screen
    }

    public static let defaults = RedaktrCaptureShortcutSettings()

    public init(rawAreaID: String?, rawWindowID: String?, rawScreenID: String?) {
        self.init(
            area: Self.choice(rawValue: rawAreaID, for: .area),
            window: Self.choice(rawValue: rawWindowID, for: .window),
            screen: Self.choice(rawValue: rawScreenID, for: .screen)
        )
    }

    public static func choice(rawValue: String?, for mode: RedaktrCaptureMode) -> RedaktrCaptureShortcutChoice {
        guard let rawValue,
              let choice = RedaktrCaptureShortcutChoice(rawValue: rawValue)
        else {
            return defaults.choice(for: mode)
        }
        return choice
    }

    public func choice(for mode: RedaktrCaptureMode) -> RedaktrCaptureShortcutChoice {
        switch mode {
        case .area:
            return area
        case .window:
            return window
        case .screen:
            return screen
        }
    }

    public mutating func setChoice(_ choice: RedaktrCaptureShortcutChoice, for mode: RedaktrCaptureMode) {
        switch mode {
        case .area:
            area = choice
        case .window:
            window = choice
        case .screen:
            screen = choice
        }
    }

    public var enabledShortcuts: [(mode: RedaktrCaptureMode, choice: RedaktrCaptureShortcutChoice)] {
        RedaktrCaptureMode.allCases.compactMap { mode in
            let choice = choice(for: mode)
            return choice.isEnabled ? (mode, choice) : nil
        }
    }

    public var conflictingChoices: Set<RedaktrCaptureShortcutChoice> {
        let choices = enabledShortcuts.map(\.choice)
        let duplicateChoices = choices.filter { choice in
            choices.filter { $0 == choice }.count > 1
        }
        return Set(duplicateChoices)
    }

    public var hasConflicts: Bool {
        !conflictingChoices.isEmpty
    }
}
