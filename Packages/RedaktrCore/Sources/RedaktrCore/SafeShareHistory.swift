import Foundation

public enum SafeShareSourceType: String, Codable, CaseIterable, Sendable {
    case fileImport
    case folderBatch
    case clipboardImport
    case clipboardProtection
    case screenshotWatch
    case capture
    case unknown

    public var displayName: String {
        switch self {
        case .fileImport:
            return "File import"
        case .folderBatch:
            return "Folder batch"
        case .clipboardImport:
            return "Clipboard import"
        case .clipboardProtection:
            return "Clipboard protection"
        case .screenshotWatch:
            return "Screenshot watch"
        case .capture:
            return "Redaktr Capture"
        case .unknown:
            return "Image"
        }
    }
}

public enum SafeShareAction: String, Codable, CaseIterable, Sendable {
    case scan
    case copyCleanedPNG
    case exportCleanedImage
    case batchExport
    case clipboardReplace

    public var displayName: String {
        switch self {
        case .scan:
            return "Scanned"
        case .copyCleanedPNG:
            return "Copied cleaned PNG"
        case .exportCleanedImage:
            return "Exported cleaned image"
        case .batchExport:
            return "Exported cleaned batch"
        case .clipboardReplace:
            return "Replaced clipboard"
        }
    }
}

public struct SafeShareHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let sourceType: SafeShareSourceType
    public let action: SafeShareAction
    public let totalFindings: Int
    public let includedFindings: Int
    public let reviewFindings: Int
    public let offFindings: Int
    public let policySummary: String?
    public let outputPath: String?
    public let batchItemCount: Int?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        sourceType: SafeShareSourceType,
        action: SafeShareAction,
        totalFindings: Int,
        includedFindings: Int,
        reviewFindings: Int,
        offFindings: Int,
        policySummary: String? = nil,
        outputPath: String? = nil,
        batchItemCount: Int? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.sourceType = sourceType
        self.action = action
        self.totalFindings = max(totalFindings, 0)
        self.includedFindings = max(includedFindings, 0)
        self.reviewFindings = max(reviewFindings, 0)
        self.offFindings = max(offFindings, 0)
        self.policySummary = policySummary
        self.outputPath = outputPath
        self.batchItemCount = batchItemCount
    }

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        sourceType: SafeShareSourceType,
        action: SafeShareAction,
        plan: RedactionPlan,
        policySummary: String? = nil,
        outputPath: String? = nil,
        batchItemCount: Int? = nil
    ) {
        self.init(
            id: id,
            occurredAt: occurredAt,
            sourceType: sourceType,
            action: action,
            totalFindings: plan.entries.count,
            includedFindings: plan.activeDetections.count,
            reviewFindings: Self.reviewFindings(in: plan),
            offFindings: plan.entries.count - plan.activeDetections.count,
            policySummary: policySummary,
            outputPath: outputPath,
            batchItemCount: batchItemCount
        )
    }

    public var findingsSummary: String {
        "\(includedFindings) included - \(reviewFindings) review - \(offFindings) off"
    }

    private static func reviewFindings(in plan: RedactionPlan) -> Int {
        plan.entries.filter { entry in
            guard entry.isActive else { return false }

            return entry.detection.suggestedAction == .review
                || entry.detection.confidence < 0.8
                || entry.detection.boundsPrecision == .lineFallback
        }.count
    }
}

public struct SafeShareHistoryStore: Codable, Equatable, Sendable {
    public private(set) var records: [SafeShareHistoryRecord]

    public init(records: [SafeShareHistoryRecord] = []) {
        self.records = records.sorted { $0.occurredAt > $1.occurredAt }
    }

    public mutating func append(_ record: SafeShareHistoryRecord, limit: Int = 50) {
        records.insert(record, at: 0)
        records = Array(records.prefix(max(limit, 0)))
    }

    public mutating func clear() {
        records.removeAll()
    }
}
