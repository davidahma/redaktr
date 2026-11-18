import Foundation

public enum RedaktrCaptureOutputMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case reviewInRedaktr
    case copyCleanedPNG
    case saveCleanedPNG
    case saveAndCopyCleanedPNG

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reviewInRedaktr:
            return "Review in Redaktr"
        case .copyCleanedPNG:
            return "Copy cleaned image to clipboard"
        case .saveCleanedPNG:
            return "Save cleaned image to folder"
        case .saveAndCopyCleanedPNG:
            return "Save and copy"
        }
    }

    public var copiesToClipboard: Bool {
        self == .copyCleanedPNG || self == .saveAndCopyCleanedPNG
    }

    public var savesToFolder: Bool {
        self == .saveCleanedPNG || self == .saveAndCopyCleanedPNG
    }
}

public enum RedaktrAutoCleanSafetyMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case reviewFirst
    case pauseIfUnsure
    case autoCleanEverything

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reviewFirst:
            return "Review first"
        case .pauseIfUnsure:
            return "AutoClean, pause if unsure"
        case .autoCleanEverything:
            return "AutoClean everything"
        }
    }

    public var detail: String {
        switch self {
        case .reviewFirst:
            return "Open every protected screenshot in Redaktr before output."
        case .pauseIfUnsure:
            return "Auto-output confident redactions, but open review when any finding needs Check."
        case .autoCleanEverything:
            return "Auto-output all selected findings, including ones marked Check."
        }
    }

    public static func fromLegacyRequiresNoReviewFindings(_ requiresNoReviewFindings: Bool) -> RedaktrAutoCleanSafetyMode {
        requiresNoReviewFindings ? .pauseIfUnsure : .autoCleanEverything
    }
}

public struct RedaktrCaptureOutputPolicy: Equatable, Sendable {
    public var mode: RedaktrCaptureOutputMode
    public var safetyMode: RedaktrAutoCleanSafetyMode

    public var requiresNoReviewFindings: Bool {
        get { safetyMode == .pauseIfUnsure }
        set { safetyMode = RedaktrAutoCleanSafetyMode.fromLegacyRequiresNoReviewFindings(newValue) }
    }

    public init(
        mode: RedaktrCaptureOutputMode = .reviewInRedaktr,
        safetyMode: RedaktrAutoCleanSafetyMode = .pauseIfUnsure
    ) {
        self.mode = mode
        self.safetyMode = safetyMode
    }

    public init(
        mode: RedaktrCaptureOutputMode = .reviewInRedaktr,
        requiresNoReviewFindings: Bool
    ) {
        self.mode = mode
        self.safetyMode = RedaktrAutoCleanSafetyMode.fromLegacyRequiresNoReviewFindings(requiresNoReviewFindings)
    }
}

public enum RedaktrCaptureOutputFallbackReason: Equatable, Sendable {
    case explicitReviewMode
    case reviewFirstMode
    case reviewFindingsPresent(Int)
}

public struct RedaktrCaptureOutputDecision: Equatable, Sendable {
    public let mode: RedaktrCaptureOutputMode
    public let fallbackReason: RedaktrCaptureOutputFallbackReason?

    public var shouldReviewInRedaktr: Bool {
        fallbackReason != nil
    }

    public init(mode: RedaktrCaptureOutputMode, fallbackReason: RedaktrCaptureOutputFallbackReason? = nil) {
        self.mode = mode
        self.fallbackReason = fallbackReason
    }

    public static func decide(
        policy: RedaktrCaptureOutputPolicy,
        reviewFindingCount: Int
    ) -> RedaktrCaptureOutputDecision {
        if policy.mode == .reviewInRedaktr {
            return RedaktrCaptureOutputDecision(
                mode: .reviewInRedaktr,
                fallbackReason: .explicitReviewMode
            )
        }

        if policy.safetyMode == .reviewFirst {
            return RedaktrCaptureOutputDecision(
                mode: .reviewInRedaktr,
                fallbackReason: .reviewFirstMode
            )
        }

        if policy.safetyMode == .pauseIfUnsure, reviewFindingCount > 0 {
            return RedaktrCaptureOutputDecision(
                mode: .reviewInRedaktr,
                fallbackReason: .reviewFindingsPresent(reviewFindingCount)
            )
        }

        return RedaktrCaptureOutputDecision(mode: policy.mode)
    }
}

public enum RedaktrAutoCleanReceiptSurface: Equatable, Sendable {
    case inAppBanner
    case systemNotification
}

public enum RedaktrAutoCleanReceiptRouter {
    public static func route(isAppActive: Bool, notificationsAvailable: Bool = true) -> RedaktrAutoCleanReceiptSurface {
        if isAppActive || !notificationsAvailable {
            return .inAppBanner
        }
        return .systemNotification
    }
}
