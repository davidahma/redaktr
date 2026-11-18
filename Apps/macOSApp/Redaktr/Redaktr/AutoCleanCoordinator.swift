import AppKit
import Foundation
import RedaktrCore

struct AutoCleanOutputCoordinator {
    func captureDecision(
        for plan: RedactionPlan,
        policy: RedaktrCaptureOutputPolicy
    ) -> RedaktrCaptureOutputDecision {
        RedaktrCaptureOutputDecision.decide(
            policy: policy,
            reviewFindingCount: reviewNeededCount(in: plan)
        )
    }

    func clipboardDecision(
        for plan: RedactionPlan,
        replacementMode: ClipboardProtectionReplacementMode
    ) -> RedaktrCaptureOutputDecision {
        RedaktrCaptureOutputDecision.decide(
            policy: RedaktrCaptureOutputPolicy(
                mode: .copyCleanedPNG,
                safetyMode: replacementMode.safetyMode
            ),
            reviewFindingCount: reviewNeededCount(in: plan)
        )
    }

    func reviewNeededCount(in plan: RedactionPlan) -> Int {
        plan.entries.filter { entry in
            guard entry.isActive else { return false }
            return entry.needsReview
        }.count
    }

    func captureReceipt(title: String, plan: RedactionPlan) -> AutoCleanReceipt {
        AutoCleanReceipt.capture(title: title, maskedCount: plan.activeDetections.count)
    }

    func clipboardReceipt(plan: RedactionPlan) -> AutoCleanReceipt {
        AutoCleanReceipt.clipboardProtected(maskedCount: plan.activeDetections.count)
    }

    func undoToken(
        clipboardSnapshot: ClipboardUndoSnapshot?,
        generatedFileURL: URL?,
        writtenClipboardChangeCount: Int?
    ) -> AutoCleanUndoToken {
        AutoCleanUndoToken(
            clipboardSnapshot: clipboardSnapshot,
            writtenClipboardChangeCount: writtenClipboardChangeCount,
            generatedFileURL: generatedFileURL,
            generatedFileIdentity: generatedFileURL.map(SourceFileIdentity.init)
        )
    }
}

@MainActor
final class AutoCleanUndoCoordinator: ObservableObject {
    @Published private(set) var token: AutoCleanUndoToken?

    private var expiryTask: Task<Void, Never>?
    private let expiryNanoseconds: UInt64

    init(expiryNanoseconds: UInt64 = 8_000_000_000) {
        self.expiryNanoseconds = expiryNanoseconds
    }

    func retain(_ token: AutoCleanUndoToken) {
        expiryTask?.cancel()
        self.token = token
        expiryTask = Task { [weak self, expiryNanoseconds] in
            try? await Task.sleep(nanoseconds: expiryNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.clear()
            }
        }
    }

    func clear() {
        expiryTask?.cancel()
        expiryTask = nil
        token = nil
    }

    @discardableResult
    func undoLatest(clipboardProtectionController: ClipboardProtectionController) -> Bool {
        guard let token else { return false }

        var didUndo = false
        if let url = token.generatedFileURL, token.generatedFileIdentity?.isSameExistingFile(as: url) == true {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                didUndo = true
            } catch {
                // The generated file may have moved or its folder permission may have expired.
            }
        }
        let pasteboard = RedaktrPasteboard.current
        if let snapshot = token.clipboardSnapshot, let generation = token.writtenClipboardChangeCount,
           snapshot.restore(to: pasteboard, ifOwnedGeneration: generation) {
            clipboardProtectionController.markHandled(changeCount: pasteboard.changeCount)
            didUndo = true
        }
        clear()
        return didUndo
    }
}
