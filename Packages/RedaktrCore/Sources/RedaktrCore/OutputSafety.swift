import Foundation

public enum ImageScanState: Equatable, Sendable {
    case queued, scanning, succeeded, failed, cancelled, manuallyReviewed

    public var allowsOutput: Bool {
        self == .succeeded || self == .manuallyReviewed
    }
}

/// Captures File System identity at import so that renamed files and hard links
/// can still be recognized when the user chooses an export destination.
public struct SourceFileIdentity {
    private let sourceURL: URL
    private let volume: UInt64?
    private let inode: UInt64?

    public init(_ sourceURL: URL) {
        self.sourceURL = sourceURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.resolvingSymlinksInPath().path)
        volume = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    public func matches(_ destination: URL) -> Bool {
        if sourceURL.standardizedFileURL.resolvingSymlinksInPath() == destination.standardizedFileURL.resolvingSymlinksInPath() {
            return true
        }
        return isSameExistingFile(as: destination)
    }

    public func isSameExistingFile(as destination: URL) -> Bool {
        let other = SourceFileIdentity(destination)
        return volume != nil && inode != nil && volume == other.volume && inode == other.inode
    }
}

/// Builds a batch out of sight and publishes its directory only after every file succeeds.
public enum BatchOutputWriter {
    public static func write(
        in root: URL,
        populate: (URL) throws -> Void
    ) throws -> URL {
        let manager = FileManager.default
        let staging = root.appendingPathComponent(".redaktr-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try populate(staging)
            var number = 1
            while true {
                let name = number == 1 ? "Redaktr Cleaned" : "Redaktr Cleaned \(number)"
                let output = root.appendingPathComponent(name, isDirectory: true)
                do {
                    try manager.moveItem(at: staging, to: output)
                    return output
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    number += 1
                }
            }
        } catch {
            // Surface a cleanup failure to the caller instead of reporting a successful export.
            try manager.removeItem(at: staging)
            throw error
        }
    }
}
