import Foundation

public struct ScreenshotWatchCandidate: Hashable, Sendable {
    public let url: URL
    public let fileSize: Int64
    public let modificationDate: Date

    public init(url: URL, fileSize: Int64, modificationDate: Date) {
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public var identity: String {
        url.standardizedFileURL.path
    }
}

public enum ScreenshotFolderWatchSnapshot {
    public static func candidates(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) -> [ScreenshotWatchCandidate] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isHiddenKey,
            .contentTypeKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .compactMap { url -> ScreenshotWatchCandidate? in
                guard ImageImporter.isSupportedImageURL(url) else { return nil }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                guard values.isRegularFile == true, values.isHidden != true else { return nil }

                return ScreenshotWatchCandidate(
                    url: url,
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { lhs, rhs in
                lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
    }
}

public struct ScreenshotFolderWatchPlan: Sendable {
    public let settleInterval: TimeInterval

    private var knownCandidateIDs: Set<String>
    private var pendingCandidates: [String: PendingCandidate]

    public init(settleInterval: TimeInterval = 1.0) {
        self.settleInterval = settleInterval
        self.knownCandidateIDs = []
        self.pendingCandidates = [:]
    }

    public mutating func seedKnownFiles(_ candidates: [ScreenshotWatchCandidate]) {
        knownCandidateIDs.formUnion(candidates.map(\.identity))
        for candidate in candidates {
            pendingCandidates.removeValue(forKey: candidate.identity)
        }
    }

    public mutating func observe(_ candidates: [ScreenshotWatchCandidate], at date: Date) {
        let currentIDs = Set(candidates.map(\.identity))
        pendingCandidates = pendingCandidates.filter { currentIDs.contains($0.key) }

        for candidate in candidates where !knownCandidateIDs.contains(candidate.identity) {
            if var pendingCandidate = pendingCandidates[candidate.identity] {
                if pendingCandidate.candidate.fileSize != candidate.fileSize
                    || pendingCandidate.candidate.modificationDate != candidate.modificationDate {
                    pendingCandidate.candidate = candidate
                    pendingCandidate.lastChangedAt = date
                    pendingCandidates[candidate.identity] = pendingCandidate
                }
            } else {
                pendingCandidates[candidate.identity] = PendingCandidate(
                    candidate: candidate,
                    lastChangedAt: date
                )
            }
        }
    }

    public mutating func readyCandidates(
        afterObserving candidates: [ScreenshotWatchCandidate],
        at date: Date
    ) -> [ScreenshotWatchCandidate] {
        observe(candidates, at: date)

        let ready = pendingCandidates.values
            .filter { date.timeIntervalSince($0.lastChangedAt) >= settleInterval }
            .map(\.candidate)
            .sorted { lhs, rhs in
                lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }

        for candidate in ready {
            knownCandidateIDs.insert(candidate.identity)
            pendingCandidates.removeValue(forKey: candidate.identity)
        }

        return ready
    }
}

private struct PendingCandidate: Sendable {
    var candidate: ScreenshotWatchCandidate
    var lastChangedAt: Date
}
