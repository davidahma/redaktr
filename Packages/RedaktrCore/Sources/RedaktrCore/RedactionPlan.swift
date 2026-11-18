import CoreGraphics
import Foundation

public struct RedactionPlan: Equatable, Sendable {
    public static let empty = RedactionPlan(entries: [])

    public private(set) var entries: [RedactionPlanEntry]

    public var detections: [Detection] {
        entries.map(\.detection)
    }

    public var activeDetections: [Detection] {
        entries.filter(\.isActive).map(\.detection)
    }

    public var manualDetections: [Detection] {
        entries.filter { $0.detection.source == .user }.map(\.detection)
    }

    public init(
        textDetections: [Detection] = [],
        visionDetections: [Detection] = [],
        manualDetections: [Detection] = [],
        manualActiveStates: [Detection.ID: Bool] = [:]
    ) {
        let merged = textDetections + visionDetections + manualDetections
        entries = Self.resolveOverlaps(in: merged, manualActiveStates: manualActiveStates).map {
            RedactionPlanEntry(detection: $0, isActive: manualActiveStates[$0.id] ?? ($0.suggestedAction != .ignore))
        }
    }

    private init(entries: [RedactionPlanEntry]) {
        self.entries = entries
    }

    fileprivate mutating func applyHistorySnapshot(_ snapshot: ManualRedactionSnapshot) {
        let currentActiveStates = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.isActive) })

        for change in snapshot.changes {
            if var entry = change.entry {
                if let currentActiveState = currentActiveStates[entry.id] {
                    entry.isActive = currentActiveState
                }
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index] = entry
                } else {
                    entries.append(entry)
                }
            } else {
                entries.removeAll { $0.id == change.id }
            }
        }

        entries = Self.sortEntriesInReadingOrder(entries)
    }

    public mutating func setActive(_ isActive: Bool, for id: Detection.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isActive = isActive
    }

    public func settingActive(_ isActive: Bool, for id: Detection.ID) -> RedactionPlan {
        var copy = self
        copy.setActive(isActive, for: id)
        return copy
    }

    @discardableResult
    public mutating func addManualRedaction(
        bounds: CGRect,
        label: String = "Manual redaction",
        reason: String = "Added by the user."
    ) -> Detection.ID? {
        guard let bounds = Self.validManualBounds(bounds) else { return nil }

        let detection = Self.manualRedaction(bounds: bounds, label: label, reason: reason)
        entries.append(RedactionPlanEntry(detection: detection, isActive: true))
        entries = Self.sortEntriesInReadingOrder(entries)
        return detection.id
    }

    @discardableResult
    public mutating func updateManualRedaction(id: Detection.ID, bounds: CGRect) -> Bool {
        guard
            let index = entries.firstIndex(where: { $0.id == id }),
            entries[index].detection.source == .user,
            let bounds = Self.validManualBounds(bounds)
        else {
            return false
        }

        entries[index].detection = Self.replacingBounds(for: entries[index].detection, with: bounds)
        entries = Self.sortEntriesInReadingOrder(entries)
        return true
    }

    @discardableResult
    public mutating func updateRedactionBounds(id: Detection.ID, bounds: CGRect) -> Bool {
        guard
            let index = entries.firstIndex(where: { $0.id == id }),
            let bounds = Self.validManualBounds(bounds)
        else {
            return false
        }

        entries[index].detection = Self.replacingBoundsAsUserAdjusted(
            for: entries[index].detection,
            with: bounds
        )
        entries = Self.sortEntriesInReadingOrder(entries)
        return true
    }

    @discardableResult
    public mutating func resetRedactionBounds(id: Detection.ID) -> Bool {
        guard
            let index = entries.firstIndex(where: { $0.id == id }),
            entries[index].detection.originalNormalizedBounds != nil
        else {
            return false
        }

        entries[index].detection = Self.resettingBounds(for: entries[index].detection)
        entries = Self.sortEntriesInReadingOrder(entries)
        return true
    }

    @discardableResult
    public mutating func removeManualRedaction(id: Detection.ID) -> Bool {
        guard
            let index = entries.firstIndex(where: { $0.id == id }),
            entries[index].detection.source == .user
        else {
            return false
        }

        entries.remove(at: index)
        return true
    }

    public static func manualRedaction(
        bounds: CGRect,
        label: String = "Manual redaction",
        reason: String = "Added by the user."
    ) -> Detection {
        Detection(
            kind: .unknown,
            label: label,
            confidence: 1,
            normalizedBounds: bounds,
            source: .user,
            reason: reason,
            suggestedAction: .redact,
            boundsPrecision: .manual
        )
    }

    private static func validManualBounds(_ bounds: CGRect) -> CGRect? {
        let rect = bounds.standardized
        let minX = min(max(rect.minX, 0), 1)
        let minY = min(max(rect.minY, 0), 1)
        let maxX = min(max(rect.maxX, 0), 1)
        let maxY = min(max(rect.maxY, 0), 1)
        let width = maxX - minX
        let height = maxY - minY

        guard width >= 0.002, height >= 0.002 else { return nil }

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func replacingBounds(for detection: Detection, with bounds: CGRect) -> Detection {
        Detection(
            id: detection.id,
            kind: detection.kind,
            label: detection.label,
            confidence: detection.confidence,
            normalizedBounds: bounds,
            source: detection.source,
            reason: detection.reason,
            matchedText: detection.matchedText,
            matchedRange: detection.matchedRange,
            suggestedAction: detection.suggestedAction,
            boundsPrecision: detection.boundsPrecision,
            originalNormalizedBounds: detection.originalNormalizedBounds,
            originalSource: detection.originalSource,
            originalReason: detection.originalReason,
            originalBoundsPrecision: detection.originalBoundsPrecision
        )
    }

    private static func replacingBoundsAsUserAdjusted(for detection: Detection, with bounds: CGRect) -> Detection {
        let isAlreadyAdjusted = detection.originalNormalizedBounds != nil
        return Detection(
            id: detection.id,
            kind: detection.kind,
            label: detection.label,
            confidence: detection.confidence,
            normalizedBounds: bounds,
            source: .user,
            reason: isAlreadyAdjusted || detection.source == .user
                ? detection.reason
                : "\(detection.reason) Bounds adjusted by the user.",
            matchedText: detection.matchedText,
            matchedRange: detection.matchedRange,
            suggestedAction: detection.suggestedAction,
            boundsPrecision: .manual,
            originalNormalizedBounds: detection.originalNormalizedBounds ?? detection.normalizedBounds,
            originalSource: detection.originalSource ?? detection.source,
            originalReason: detection.originalReason ?? detection.reason,
            originalBoundsPrecision: detection.originalBoundsPrecision ?? detection.boundsPrecision
        )
    }

    private static func resettingBounds(for detection: Detection) -> Detection {
        Detection(
            id: detection.id,
            kind: detection.kind,
            label: detection.label,
            confidence: detection.confidence,
            normalizedBounds: detection.originalNormalizedBounds ?? detection.normalizedBounds,
            source: detection.originalSource ?? detection.source,
            reason: detection.originalReason ?? detection.reason,
            matchedText: detection.matchedText,
            matchedRange: detection.matchedRange,
            suggestedAction: detection.suggestedAction,
            boundsPrecision: detection.originalBoundsPrecision ?? detection.boundsPrecision
        )
    }

    private static func resolveOverlaps(in detections: [Detection], manualActiveStates: [Detection.ID: Bool]) -> [Detection] {
        detections
            .sorted(by: detectionPrecedence)
            .reduce(into: [Detection]()) { accepted, candidate in
                let candidateRect = candidate.normalizedBounds.standardized
                let isDuplicate = accepted.contains { existing in
                    let existingRect = existing.normalizedBounds.standardized
                    guard candidateRect.intersects(existingRect) else { return false }
                    guard manualActiveStates[existing.id] != false, existing.suggestedAction != .ignore else {
                        return false
                    }
                    if existing.source == .user && candidate.source != .user {
                        // A hand-drawn box supersedes only automatic masks it completely covers.
                        return existingRect.contains(candidateRect)
                    }
                    guard candidate.source == existing.source,
                          candidate.kind == existing.kind, candidate.label == existing.label else { return false }
                    if candidate.source == .deterministic, candidate.matchedRange != nil,
                       candidate.matchedRange == existing.matchedRange, candidate.matchedText == existing.matchedText {
                        // A precise box for this same match may replace a whole-line fallback.
                        return existingRect.contains(candidateRect)
                            || (existing.boundsPrecision == .tight && candidate.boundsPrecision == .lineFallback
                                && candidateRect.contains(existingRect))
                    }
                    return candidate == existing
                }

                if !isDuplicate {
                    accepted.append(candidate)
                }
            }
            .sorted(by: readingOrder)
    }

    private static func sortEntriesInReadingOrder(_ entries: [RedactionPlanEntry]) -> [RedactionPlanEntry] {
        entries.sorted { readingOrder($0.detection, $1.detection) }
    }

    private static func readingOrder(_ lhs: Detection, _ rhs: Detection) -> Bool {
        if lhs.normalizedBounds.minY != rhs.normalizedBounds.minY {
            return lhs.normalizedBounds.minY > rhs.normalizedBounds.minY
        }
        return lhs.normalizedBounds.minX < rhs.normalizedBounds.minX
    }

    private static func detectionPrecedence(_ lhs: Detection, _ rhs: Detection) -> Bool {
        if lhs.boundsPrecision != rhs.boundsPrecision {
            return precisionRank(lhs.boundsPrecision) > precisionRank(rhs.boundsPrecision)
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        let lhsArea = lhs.normalizedBounds.width * lhs.normalizedBounds.height
        let rhsArea = rhs.normalizedBounds.width * rhs.normalizedBounds.height
        if lhsArea != rhsArea {
            return lhsArea < rhsArea
        }

        return lhs.label < rhs.label
    }

    private static func precisionRank(_ precision: DetectionBoundsPrecision) -> Int {
        switch precision {
        case .manual: 5
        case .tight: 4
        case .lineFallback: 2
        case .unknown: 1
        }
    }


}

public struct RedactionPlanEntry: Identifiable, Equatable, Sendable {
    public var id: Detection.ID { detection.id }
    public var detection: Detection
    public var isActive: Bool

    public init(detection: Detection, isActive: Bool) {
        self.detection = detection
        self.isActive = isActive
    }
}

public struct ManualRedactionEditHistory: Equatable, Sendable {
    private var undoSnapshots: [ManualRedactionSnapshot] = []
    private var redoSnapshots: [ManualRedactionSnapshot] = []

    public init() {}

    public var canUndo: Bool {
        !undoSnapshots.isEmpty
    }

    public var canRedo: Bool {
        !redoSnapshots.isEmpty
    }

    public mutating func reset() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
    }

    @discardableResult
    public mutating func recordChange(from oldPlan: RedactionPlan, to newPlan: RedactionPlan) -> Bool {
        let changedIDs = Self.changedDetectionIDs(from: oldPlan, to: newPlan)
        guard !changedIDs.isEmpty else { return false }

        let oldSnapshot = ManualRedactionSnapshot(plan: oldPlan, changedIDs: changedIDs)

        undoSnapshots.append(oldSnapshot)
        redoSnapshots.removeAll()
        return true
    }

    @discardableResult
    public mutating func undo(in plan: inout RedactionPlan) -> Bool {
        guard let snapshot = undoSnapshots.popLast() else { return false }

        redoSnapshots.append(ManualRedactionSnapshot(plan: plan, changedIDs: snapshot.changedIDs))
        plan.applyHistorySnapshot(snapshot)
        return true
    }

    @discardableResult
    public mutating func redo(in plan: inout RedactionPlan) -> Bool {
        guard let snapshot = redoSnapshots.popLast() else { return false }

        undoSnapshots.append(ManualRedactionSnapshot(plan: plan, changedIDs: snapshot.changedIDs))
        plan.applyHistorySnapshot(snapshot)
        return true
    }

    private static func changedDetectionIDs(from oldPlan: RedactionPlan, to newPlan: RedactionPlan) -> [Detection.ID] {
        let oldDetections = Dictionary(uniqueKeysWithValues: oldPlan.entries.map { ($0.id, $0.detection) })
        let newDetections = Dictionary(uniqueKeysWithValues: newPlan.entries.map { ($0.id, $0.detection) })
        return Set(oldDetections.keys)
            .union(newDetections.keys)
            .filter { oldDetections[$0] != newDetections[$0] }
            .sorted { $0.uuidString < $1.uuidString }
    }
}

fileprivate struct ManualRedactionSnapshot: Equatable, Sendable {
    let changes: [ManualRedactionSnapshotChange]

    var changedIDs: [Detection.ID] {
        changes.map(\.id)
    }

    init(plan: RedactionPlan, changedIDs: [Detection.ID]) {
        let entriesByID = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.id, $0) })
        changes = changedIDs.map { id in
            ManualRedactionSnapshotChange(id: id, entry: entriesByID[id])
        }
    }
}

fileprivate struct ManualRedactionSnapshotChange: Equatable, Sendable {
    let id: Detection.ID
    let entry: RedactionPlanEntry?
}
