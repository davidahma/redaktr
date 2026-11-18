import AppKit
import CoreGraphics
import RedaktrCore
import SwiftUI

struct BatchReviewItem: Identifiable {
    let id: UUID
    let sourceURL: URL?
    let sourceIdentity: SourceFileIdentity?
    let sourceLabel: String?
    let sourceType: SafeShareSourceType
    let importedImage: ImportedImage
    var redactionPlan: RedactionPlan
    var selectedDetectionID: Detection.ID?
    var manualEditHistory: ManualRedactionEditHistory
    var reviewStatusNote: String
    var errorText: String?
    var scanState: ImageScanState
    var isChecking: Bool { scanState == .scanning }
    var didScan: Bool { scanState.allowsOutput }
    var didReviewInBatch: Bool

    init(
        id: UUID = UUID(),
        sourceURL: URL?,
        sourceLabel: String? = nil,
        sourceType: SafeShareSourceType = .unknown,
        importedImage: ImportedImage,
        redactionPlan: RedactionPlan = .empty,
        selectedDetectionID: Detection.ID? = nil,
        manualEditHistory: ManualRedactionEditHistory = ManualRedactionEditHistory(),
        reviewStatusNote: String,
        errorText: String? = nil,
        scanState: ImageScanState = .queued,
        didReviewInBatch: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        sourceIdentity = sourceURL.map(SourceFileIdentity.init)
        self.sourceLabel = sourceLabel
        self.sourceType = sourceType
        self.importedImage = importedImage
        self.redactionPlan = redactionPlan
        self.selectedDetectionID = selectedDetectionID
        self.manualEditHistory = manualEditHistory
        self.reviewStatusNote = reviewStatusNote
        self.errorText = errorText
        self.scanState = scanState
        self.didReviewInBatch = didReviewInBatch
    }

    var displayName: String {
        if let sourceLabel {
            return sourceLabel
        }
        guard let sourceURL else { return "Clipboard image" }
        let name = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Image" : name
    }

    var findingCount: Int {
        redactionPlan.entries.count
    }

    var activeCount: Int {
        redactionPlan.activeDetections.count
    }

    var reviewNeededCount: Int {
        redactionPlan.entries.filter { entry in
            entry.isActive && entry.needsReview
        }.count
    }

    var needsBatchReview: Bool {
        didScan && findingCount > 0 && !didReviewInBatch
    }

    var statusLabel: String {
        if isChecking { return "Scanning" }
        if errorText != nil { return "Needs attention" }
        if scanState == .cancelled { return "Cancelled" }
        if scanState == .failed { return "Scan failed" }
        if scanState == .manuallyReviewed { return "Manually reviewed" }
        if !didScan { return "Queued" }
        if findingCount == 0 { return "No findings" }
        if didReviewInBatch { return "Reviewed" }
        if reviewNeededCount > 0 { return "\(reviewNeededCount) to check" }
        return "\(activeCount) to redact"
    }

    var statusIcon: String {
        if isChecking { return "hourglass" }
        if errorText != nil { return "exclamationmark.triangle" }
        if !didScan { return "clock" }
        if findingCount == 0 { return "checkmark.circle" }
        if didReviewInBatch { return "checkmark.circle" }
        if reviewNeededCount > 0 { return "exclamationmark.circle" }
        return "checkmark.seal"
    }

    var statusColor: Color {
        if errorText != nil || reviewNeededCount > 0 { return .orange }
        if isChecking { return .accentColor }
        if !didScan { return .secondary }
        if didReviewInBatch { return .secondary }
        return .green
    }
}

struct WatchedAlertQueue<Element> {
    private(set) var items: [Element]

    init(items: [Element] = []) {
        self.items = items
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var count: Int {
        items.count
    }

    var first: Element? {
        items.first
    }

    mutating func enqueue(
        _ item: Element,
        limit: Int = 20,
        replacing shouldReplace: (Element) -> Bool
    ) {
        items.removeAll(where: shouldReplace)
        items.insert(item, at: 0)
        items = Array(items.prefix(max(limit, 0)))
    }

    mutating func removeAll() {
        items.removeAll()
    }

    func firstIndex(where predicate: (Element) -> Bool) -> Int? {
        items.firstIndex(where: predicate)
    }

    mutating func remove(at index: Int) -> Element {
        items.remove(at: index)
    }
}

struct BatchScanInput {
    let sourceFilename: String?
    let id: BatchReviewItem.ID
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
    let manualDetections: [Detection]
    let manualActiveStates: [Detection.ID: Bool]
}

struct ExportLocation {
    let url: URL
    let isDirectory: Bool
}

enum CompletionBannerAction {
    case revealLastExport
    case reviewLatestWatchedScreenshot
    case reviewLastAutoClean
    case undoLastAutoClean
    case openNotificationSettings

    var title: String {
        switch self {
        case .revealLastExport:
            return "Reveal"
        case .reviewLatestWatchedScreenshot, .reviewLastAutoClean:
            return "Review"
        case .undoLastAutoClean:
            return "Undo"
        case .openNotificationSettings:
            return "Open Settings"
        }
    }
}

enum CaptureAutoOutputError: Error {
    case missingSaveFolder
}

struct AutoCleanReceipt {
    let title: String
    let notificationBody: String
    let primaryAction: CompletionBannerAction?
    let secondaryAction: CompletionBannerAction?

    static func capture(title: String, maskedCount: Int) -> AutoCleanReceipt {
        AutoCleanReceipt(
            title: "\(title) · \(Self.maskedCopy(for: maskedCount))",
            notificationBody: "Redaktr scanned locally and masked \(Self.itemCopy(for: maskedCount)) in a cleaned PNG. Open Redaktr to review or undo recent AutoClean output.",
            primaryAction: .reviewLastAutoClean,
            secondaryAction: .undoLastAutoClean
        )
    }

    static func clipboardProtected(maskedCount: Int) -> AutoCleanReceipt {
        AutoCleanReceipt(
            title: "Clipboard protected · \(maskedCopy(for: maskedCount))",
            notificationBody: "Redaktr replaced the image clipboard with a cleaned PNG after masking \(itemCopy(for: maskedCount)). Open Redaktr to review or undo recent AutoClean output.",
            primaryAction: .reviewLastAutoClean,
            secondaryAction: .undoLastAutoClean
        )
    }

    private static func maskedCopy(for count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items") masked"
    }

    private static func itemCopy(for count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items")"
    }
}

struct AutoCleanUndoToken {
    let clipboardSnapshot: ClipboardUndoSnapshot?
    let writtenClipboardChangeCount: Int?
    let generatedFileURL: URL?
    let generatedFileIdentity: SourceFileIdentity?
}

enum RedaktrHelpSheet: String, Identifiable {
    case onboarding
    case helpCenter

    var id: String { rawValue }
}

struct FindingGroup: Identifiable {
    var id: FindingCategory { category }
    let category: FindingCategory
    let entries: [RedactionPlanEntry]
}

extension BatchReviewItem {
    func containsFindingCategory(_ category: FindingCategory) -> Bool {
        redactionPlan.entries.contains { category.contains($0.detection) }
    }
}

struct ReviewedOutput: Equatable {
    let itemID: UUID
    let plan: RedactionPlan
    let scanState: ImageScanState

    init(_ item: BatchReviewItem) {
        itemID = item.id
        plan = item.redactionPlan
        scanState = item.scanState
    }
}

enum ShareAction: Equatable {
    case copy
    case export
    case batchExport

    var continueLabel: String {
        switch self {
        case .copy: return "Copy anyway"
        case .export: return "Export anyway"
        case .batchExport: return "Export batch anyway"
        }
    }
}

enum BatchReviewFilter: String, CaseIterable, Identifiable {
    case all
    case findings
    case clean

    var id: Self { self }

    var displayName: String {
        switch self {
        case .all: return "All images"
        case .findings: return "Findings"
        case .clean: return "Clean"
        }
    }

    func includes(_ item: BatchReviewItem) -> Bool {
        switch self {
        case .all:
            return true
        case .findings:
            return item.findingCount > 0
        case .clean:
            return item.didScan && item.findingCount == 0 && item.errorText == nil
        }
    }
}

enum FindingFilter: String, CaseIterable, Identifiable {
    case all
    case needsReview
    case included
    case off

    var id: Self { self }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .needsReview: return "Check"
        case .included: return "Redact"
        case .off: return "Visible"
        }
    }

    func includes(_ entry: RedactionPlanEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .needsReview:
            return entry.isActive && entry.needsReview
        case .included:
            return entry.isActive
        case .off:
            return !entry.isActive
        }
    }
}

enum FindingCategory: String, CaseIterable, Identifiable {
    case secrets
    case emails
    case people
    case visualCodes
    case customerAccount
    case infrastructure
    case payments
    case phones
    case review

    var id: Self { self }

    var displayName: String {
        switch self {
        case .secrets: return "Secrets"
        case .emails: return "Emails"
        case .people: return "People"
        case .visualCodes: return "Visual codes"
        case .customerAccount: return "Customer/account"
        case .infrastructure: return "Infrastructure"
        case .payments: return "Payments"
        case .phones: return "Phones"
        case .review: return "Review"
        }
    }

    var systemImage: String {
        switch self {
        case .secrets: return "key"
        case .emails: return "envelope"
        case .people: return "person.crop.rectangle"
        case .visualCodes: return "qrcode.viewfinder"
        case .customerAccount: return "person.text.rectangle"
        case .infrastructure: return "network"
        case .payments: return "creditcard"
        case .phones: return "phone"
        case .review: return "exclamationmark.bubble"
        }
    }

    func contains(_ detection: Detection) -> Bool {
        switch self {
        case .secrets:
            return detection.kind == .apiKey || detection.kind == .secret || detection.kind == .url
        case .emails:
            return detection.kind == .email
        case .people:
            return detection.kind == .face
        case .visualCodes:
            return detection.kind == .barcode
        case .customerAccount:
            return detection.label == "Account/customer ID"
        case .infrastructure:
            return detection.kind == .ipAddress
        case .payments:
            return detection.kind == .creditCard
        case .phones:
            return detection.kind == .phoneNumber
        case .review:
            return detection.kind == .unknown && detection.label != "Account/customer ID"
        }
    }
}

extension RedactionPlanEntry {
    var needsReview: Bool {
        detection.suggestedAction == .review
            || detection.confidence < 0.8
            || detection.boundsPrecision == .lineFallback
    }
}
