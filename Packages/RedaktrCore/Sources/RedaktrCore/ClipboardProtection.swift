import Foundation

public enum ClipboardProtectionReplacementMode: String, CaseIterable, Codable, Hashable, Sendable {
    case reviewFirst
    case pauseIfUnsure
    case autoCleanEverything
    case askBeforeReplace
    case autoReplace

    public static var allCases: [ClipboardProtectionReplacementMode] {
        [.reviewFirst, .pauseIfUnsure, .autoCleanEverything]
    }

    public var displayName: String {
        normalized.displayName
    }

    public var detail: String {
        normalized.detail
    }

    public var safetyMode: RedaktrAutoCleanSafetyMode {
        normalized
    }

    public var normalizedReplacementMode: ClipboardProtectionReplacementMode {
        switch self {
        case .askBeforeReplace:
            return .reviewFirst
        case .autoReplace:
            return .pauseIfUnsure
        case .reviewFirst, .pauseIfUnsure, .autoCleanEverything:
            return self
        }
    }

    private var normalized: RedaktrAutoCleanSafetyMode {
        switch self {
        case .reviewFirst, .askBeforeReplace:
            return .reviewFirst
        case .pauseIfUnsure, .autoReplace:
            return .pauseIfUnsure
        case .autoCleanEverything:
            return .autoCleanEverything
        }
    }
}

public struct ClipboardProtectionConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var replacementMode: ClipboardProtectionReplacementMode

    public init(
        isEnabled: Bool = false,
        replacementMode: ClipboardProtectionReplacementMode = .pauseIfUnsure
    ) {
        self.isEnabled = isEnabled
        self.replacementMode = replacementMode.normalizedReplacementMode
    }
}

public enum ClipboardProtectionScanDecision: Equatable, Sendable {
    case ignore
    case wait
    case scan(changeCount: Int)
}

public struct ClipboardProtectionMonitorPlan: Sendable {
    public let settleInterval: TimeInterval

    private var pendingImageChange: PendingClipboardImageChange?
    private var handledChangeCounts: Set<Int>

    public init(settleInterval: TimeInterval = 0.75) {
        self.settleInterval = settleInterval
        self.pendingImageChange = nil
        self.handledChangeCounts = []
    }

    public mutating func observe(
        changeCount: Int,
        containsImage: Bool,
        at date: Date
    ) -> ClipboardProtectionScanDecision {
        guard !handledChangeCounts.contains(changeCount) else {
            pendingImageChange = nil
            return .ignore
        }

        guard containsImage else {
            pendingImageChange = nil
            handledChangeCounts.insert(changeCount)
            trimHandledChangeCounts(keeping: 12)
            return .ignore
        }

        if let pendingImageChange, pendingImageChange.changeCount == changeCount {
            guard date.timeIntervalSince(pendingImageChange.firstObservedAt) >= settleInterval else {
                return .wait
            }

            self.pendingImageChange = nil
            handledChangeCounts.insert(changeCount)
            trimHandledChangeCounts(keeping: 12)
            return .scan(changeCount: changeCount)
        }

        pendingImageChange = PendingClipboardImageChange(
            changeCount: changeCount,
            firstObservedAt: date
        )
        return .wait
    }

    public mutating func markHandled(changeCount: Int) {
        handledChangeCounts.insert(changeCount)
        pendingImageChange = pendingImageChange?.changeCount == changeCount ? nil : pendingImageChange
        trimHandledChangeCounts(keeping: 12)
    }

    private mutating func trimHandledChangeCounts(keeping limit: Int) {
        guard handledChangeCounts.count > limit else { return }

        handledChangeCounts = Set(handledChangeCounts.sorted().suffix(limit))
    }
}

private struct PendingClipboardImageChange: Sendable {
    let changeCount: Int
    let firstObservedAt: Date
}
