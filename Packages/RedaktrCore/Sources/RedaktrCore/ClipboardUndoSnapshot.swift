import AppKit

@MainActor
public struct ClipboardUndoSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    public let changeCount: Int

    public static func capture(from pasteboard: NSPasteboard) -> ClipboardUndoSnapshot {
        let generation = pasteboard.changeCount
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                representations[type] = item.data(forType: type)
            }
            return representations
        }
        return ClipboardUndoSnapshot(items: items, changeCount: generation)
    }

    /// Returns the generation owned by this write. Skip stale async results.
    public func replace(with data: Data, in pasteboard: NSPasteboard) throws -> Int? {
        guard pasteboard.changeCount == changeCount else { return nil }
        let ownedGeneration = pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            _ = restore(to: pasteboard, ifOwnedGeneration: ownedGeneration)
            throw RedaktrCoreError.imageDestinationFailed
        }
        return ownedGeneration
    }

    public func restore(to pasteboard: NSPasteboard, ifOwnedGeneration generation: Int) -> Bool {
        let restored = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        guard pasteboard.changeCount == generation else { return false }
        pasteboard.clearContents()
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }
}
