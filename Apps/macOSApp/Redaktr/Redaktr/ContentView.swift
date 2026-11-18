import AppKit
import RedaktrCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @StateObject private var applicationInstallController = ApplicationInstallController()
    @StateObject private var screenshotWatchController = ScreenshotWatchController()
    @StateObject private var clipboardProtectionController = ClipboardProtectionController()
    @StateObject private var globalCaptureShortcutController = GlobalCaptureShortcutController()
    @StateObject private var autoCleanUndoCoordinator = AutoCleanUndoCoordinator()
    private let autoCleanCoordinator = AutoCleanOutputCoordinator()
    @AppStorage(RedaktrSettingsStorage.customTermsKey) private var customTermsText = ""
    @AppStorage(RedaktrSettingsStorage.customRegexesKey) private var customRegexesText = ""
    @AppStorage(RedaktrSettingsStorage.allowlistKey) private var allowlistText = ""
    @AppStorage(RedaktrSettingsStorage.policyPresetKey) private var policyPresetID = ""
    @AppStorage(RedaktrSettingsStorage.policySourceKey) private var policySourceID = PolicySource.local.rawValue
    @AppStorage(RedaktrSettingsStorage.detectorCategoryPreferencesKey) private var detectorCategoryPreferencesData = Data()
    @State private var image: NSImage?
    @State private var cgImage: CGImage?
    @State private var imageOrientation: CGImagePropertyOrientation = .up
    @State private var redactionPlan = RedactionPlan.empty
    private var selectedItem: BatchReviewItem? {
        batchItems.first { $0.id == selectedBatchItemID }
    }
    private var isChecking: Bool { selectedItem?.isChecking == true }
    private var canShareSelected: Bool { selectedItem?.scanState.allowsOutput == true }
    @State private var reviewStatusNote = "Open, paste, or drop a PNG, JPEG, TIFF, or HEIC image. Redaktr works on device; review before sharing."
    @State private var errorText: String?
    @State private var customSettingsRescanTask: Task<Void, Never>?
    @State private var shouldNotifyCustomSettingsRescanCompletion = false
    @State private var selectedDetectionID: Detection.ID?
    @State private var isManualEditing = false
    @State private var keepsManualEditingAfterCommit = false
    @State private var isPreviewingRedactedOutput = false
    @State private var redactedPreviewImage: NSImage?
    @State private var findingFilter: FindingFilter = .all
    @State private var pendingShareAction: ShareAction?
    @State private var pendingShareItems: [ReviewedOutput] = []
    @State private var isShowingReviewWarning = false
    @State private var completionBannerText: String?
    @State private var completionBannerAction: CompletionBannerAction?
    @State private var completionBannerSecondaryAction: CompletionBannerAction?
    @State private var completionBannerTask: Task<Void, Never>?
    @State private var manualEditHistory = ManualRedactionEditHistory()
    @State private var sourceImageURL: URL?
    @State private var didLoadLaunchFixture = false
    @State private var batchItems: [BatchReviewItem] = []
    @State private var selectedBatchItemID: BatchReviewItem.ID?
    @State private var batchFilter: BatchReviewFilter = .all
    @State private var batchCategoryFilter: FindingCategory?
    @State private var batchScanTask: Task<Void, Never>?
    @State private var batchRunID = UUID()
    @State private var includesCleanBatchExports = true
    @State private var watchedScreenshotScanTasks: [String: Task<Void, Never>] = [:]
    @State private var watchedScreenshotQueue = WatchedAlertQueue<BatchReviewItem>()
    @State private var clipboardMonitorGeneration = UUID()
    @State private var clipboardProtectionScanTasks: [Int: Task<Void, Never>] = [:]
    @State private var lastAutoCleanReviewItem: BatchReviewItem?
    @State private var captureTask: Task<Void, Never>?
    @State private var activeCaptureMode: RedaktrCaptureMode?
    @State private var sourceDisplayLabel: String?
    @State private var lastExportLocation: ExportLocation?
    @AppStorage(RedaktrOnboardingStorage.didCompleteKey) private var didCompleteOnboarding = false
    @State private var activeHelpSheet: RedaktrHelpSheet?
    @State private var lastPresentedHelpSheet: RedaktrHelpSheet?
    @State private var activeToolbarPopover: ToolbarPopover?
    #if DEBUG
    @State private var uiTestSampleStatus = "idle"
    #endif

    private var activeDetectionCount: Int {
        redactionPlan.activeDetections.count
    }

    private var redactionCountSummary: String {
        "\(activeDetectionCount) of \(redactionPlan.detections.count) will redact"
    }

    private var inactiveDetectionCount: Int {
        redactionPlan.detections.count - activeDetectionCount
    }

    private var reviewNeededCount: Int {
        autoCleanCoordinator.reviewNeededCount(in: redactionPlan)
    }

    private var isBatchReview: Bool {
        batchItems.count > 1
    }

    private var isBatchScanning: Bool {
        batchScanTask != nil
    }

    private var isCapturing: Bool {
        captureTask != nil
    }

    private var canCloseCurrentReview: Bool {
        image != nil || !batchItems.isEmpty || isChecking || isBatchScanning || isCapturing
    }

    private var closeCurrentReviewLabel: String {
        isBatchReview ? "Close Batch" : "Close Image"
    }

    private var batchImagesWithFindingsCount: Int {
        batchItems.filter { !$0.redactionPlan.entries.isEmpty }.count
    }

    private var batchCleanImagesCount: Int {
        batchItems.filter { item in
            item.scanState == .succeeded && item.redactionPlan.entries.isEmpty
        }.count
    }

    private var batchReviewedFindingImagesCount: Int {
        batchItems.filter { item in
            item.didReviewInBatch && !item.redactionPlan.entries.isEmpty
        }.count
    }

    private var filteredBatchItems: [BatchReviewItem] {
        batchItems.filter { item in
            batchFilter.includes(item)
                && (batchCategoryFilter.map { item.containsFindingCategory($0) } ?? true)
        }
    }

    private var batchFindingCategorySummaries: [(category: FindingCategory, imageCount: Int, findingCount: Int)] {
        FindingCategory.allCases.compactMap { category in
            let matchingItems = batchItems.filter { $0.containsFindingCategory(category) }
            let findingCount = matchingItems.reduce(0) { partialResult, item in
                partialResult + item.redactionPlan.entries.filter { category.contains($0.detection) }.count
            }

            guard findingCount > 0 else { return nil }
            return (category, matchingItems.count, findingCount)
        }
    }

    private var batchCategoryFilterTitle: String {
        batchCategoryFilter?.displayName ?? "All finding types"
    }

    private var batchImagesNeedingReviewCount: Int {
        batchItems.filter { $0.reviewNeededCount > 0 }.count
    }

    private var batchCompletedScanCount: Int {
        batchItems.filter { $0.didScan || $0.scanState == .failed }.count
    }

    private var batchReviewNeededCount: Int {
        batchItems.reduce(0) { partialResult, item in
            partialResult + item.reviewNeededCount
        }
    }

    private var batchExportItems: [BatchReviewItem] {
        batchItems.filter { item in
            item.scanState.allowsOutput && (includesCleanBatchExports || !item.redactionPlan.entries.isEmpty)
        }
    }

    private var canShareBatch: Bool {
        !isBatchScanning && !batchExportItems.isEmpty && batchItems.allSatisfy { $0.scanState.allowsOutput }
    }

    private var selectedEntry: RedactionPlanEntry? {
        guard
            let selectedDetectionID,
            let entry = redactionPlan.entries.first(where: { $0.id == selectedDetectionID })
        else {
            return nil
        }

        return entry
    }

    private var selectedManualRedactionID: Detection.ID? {
        guard
            let selectedEntry,
            selectedEntry.detection.source == .user
        else {
            return nil
        }

        return selectedDetectionID
    }

    private var selectedAdjustedRedactionID: Detection.ID? {
        guard
            let selectedEntry,
            selectedEntry.detection.hasAdjustedBounds
        else {
            return nil
        }

        return selectedDetectionID
    }

    private var displayedImage: NSImage? {
        if isPreviewingRedactedOutput {
            return redactedPreviewImage ?? image
        }
        return image
    }

    private var sourceDisplayName: String {
        guard image != nil else { return "Redaktr" }
        if let sourceDisplayLabel {
            return sourceDisplayLabel
        }
        guard let sourceImageURL else { return "Clipboard image" }
        let name = sourceImageURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Image" : name
    }

    private var reviewSubtitle: String {
        guard !redactionPlan.entries.isEmpty else {
            return image == nil ? "Open an image to start." : "No findings yet."
        }

        if reviewNeededCount > 0 {
            return "\(activeDetectionCount) will redact - \(reviewNeededCount) to check"
        }

        return "\(activeDetectionCount) will redact - \(inactiveDetectionCount) visible"
    }

    private let recognizer = OCRTextRecognizer()
    private let visualDetector = VisualSensitiveContentDetector()
    private let renderer = RedactionRenderer()
    private let captureService = RedaktrScreenCaptureService()

    private var customDetectionConfiguration: CustomDetectionConfiguration {
        RedaktrSettingsStorage.configuration(
            customTermsText: customTermsText,
            customRegexesText: customRegexesText,
            allowlistText: allowlistText,
            policyPresetID: policyPresetID,
            detectorCategoryPreferencesData: detectorCategoryPreferencesData
        )
    }

    private var scanStatusIcon: String {
        if isCapturing { return "camera.viewfinder" }
        if image == nil && screenshotWatchController.isRunning { return "folder" }
        if image == nil { return "checkmark.seal" }
        if errorText != nil { return "exclamationmark.triangle" }
        return "checkmark.shield"
    }

    private var scanStatusText: String {
        if let activeCaptureMode { return activeCaptureMode.displayName }
        if isBatchScanning { return "Scanning batch \(batchCompletedScanCount)/\(batchItems.count)" }
        if isChecking { return "Scanning on device" }
        if image == nil && screenshotWatchController.isRunning { return "Watching screenshot folder" }
        if image == nil { return "On-device. No account" }
        if errorText != nil { return "Needs attention" }
        if isBatchReview {
            return "\(batchItems.count) images - \(batchCleanImagesCount) clean - \(batchImagesWithFindingsCount) with findings"
        }
        if redactionPlan.entries.isEmpty { return "On-device scan complete - none found" }
        if reviewNeededCount > 0 { return "On-device scan complete - review \(reviewNeededCount)" }
        return "On-device scan complete - \(redactionPlan.entries.count) found"
    }

    private var scanStatusForeground: Color {
        if errorText != nil { return .orange }
        if isCapturing { return .accentColor }
        if image == nil && screenshotWatchController.isRunning { return .accentColor }
        if image == nil { return .secondary }
        if isBatchScanning { return .accentColor }
        if reviewNeededCount > 0 { return .orange }
        return .green
    }

    private var scanStatusBackground: Color {
        if errorText != nil { return .orange.opacity(0.12) }
        if isCapturing { return Color.accentColor.opacity(0.12) }
        if image == nil && screenshotWatchController.isRunning { return Color.accentColor.opacity(0.12) }
        if image == nil { return Color(nsColor: .controlBackgroundColor) }
        if isBatchScanning { return Color.accentColor.opacity(0.12) }
        if reviewNeededCount > 0 { return .orange.opacity(0.12) }
        return .green.opacity(0.12)
    }

    private var filteredEntries: [RedactionPlanEntry] {
        redactionPlan.entries.filter { findingFilter.includes($0) }
    }

    private var findingGroups: [FindingGroup] {
        FindingCategory.allCases.compactMap { category in
            let entries = filteredEntries.filter { category.contains($0.detection) }
            guard !entries.isEmpty else { return nil }
            return FindingGroup(category: category, entries: entries)
        }
    }

    private var shareWarningMessage: String {
        let count = pendingShareAction == .batchExport ? batchReviewNeededCount : reviewNeededCount
        let noun = count == 1 ? "finding" : "findings"
        return "\(count) \(noun) marked for redaction still need checking. Preview the cleaned output before sharing when possible."
    }

    var body: some View {
        lifecycleRootLayout
            .modifier(
                ContentPresentationModifier(
                    isShowingReviewWarning: $isShowingReviewWarning,
                    shareContinueLabel: pendingShareAction?.continueLabel ?? "Continue",
                    shareWarningMessage: shareWarningMessage,
                    continueShare: performPendingShareAction,
                    cancelShare: cancelPendingShareAction,
                    activeHelpSheet: $activeHelpSheet,
                    handleHelpSheetDismiss: handleHelpSheetDismiss,
                    helpSheetContent: helpSheetContent
                )
            )
            .modifier(
                ApplicationInstallPresentationModifier(
                    controller: applicationInstallController,
                    onPromptResolved: showFirstLaunchOnboardingIfNeeded
                )
            )
    }

    private var lifecycleRootLayout: AnyView {
        var view = AnyView(rootLayout.onDrop(of: [.fileURL, .image], isTargeted: nil, perform: handleDrop(providers:)))
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrImportClipboardImage)) { _ in
            importClipboardImage()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrCloseCurrentReview)) { _ in
            clearCurrentReview()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrToggleOutputPreview)) { _ in
            setPreviewingRedactedOutput(!isPreviewingRedactedOutput)
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrExportCleanedImage)) { _ in
            exportRedacted()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrCopyCleanedImage)) { _ in
            copyRedacted()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrRedactAllFindings)) { _ in
            setAllActive(true)
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrMakeAllFindingsVisible)) { _ in
            setAllActive(false)
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrDeleteSelectedManualRedaction)) { _ in
            deleteSelectedManualRedaction()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrUndoManualEdit)) { _ in
            undoManualEdit()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrRedoManualEdit)) { _ in
            redoManualEdit()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrCustomDetectionSettingsDidChange)) { notification in
            refreshDetectionSettings(from: notification)
            scheduleCustomSettingsRescan()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrScreenshotWatchSettingsDidChange)) { _ in
            refreshScreenshotWatch()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrClipboardProtectionSettingsDidChange)) { _ in
            refreshClipboardProtection()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrCaptureShortcutSettingsDidChange)) { _ in
            globalCaptureShortcutController.refreshRegistration()
        })
        view = AnyView(view.onReceive(
            NotificationCenter.default.publisher(for: .redaktrCaptureRequested),
            perform: handleCaptureRequestNotification
        ))
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrOpenLatestWatchedScreenshot)) { _ in
            openLatestWatchedScreenshot()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrShowHelpCenter)) { _ in
            presentHelpSheet(.helpCenter)
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .redaktrShowOnboarding)) { _ in
            presentHelpSheet(.onboarding)
        })
        view = AnyView(view.onAppear(perform: handleAppear))
        view = AnyView(view.onDisappear(perform: handleDisappear))
        view = AnyView(view.onChange(of: customTermsText) { _, _ in
            scheduleCustomSettingsRescan()
        })
        view = AnyView(view.onChange(of: customRegexesText) { _, _ in
            scheduleCustomSettingsRescan()
        })
        view = AnyView(view.onChange(of: allowlistText) { _, _ in
            scheduleCustomSettingsRescan()
        })
        view = AnyView(view.onChange(of: policyPresetID) { _, _ in
            scheduleCustomSettingsRescan()
        })
        view = AnyView(view.onChange(of: detectorCategoryPreferencesData) { _, _ in
            scheduleCustomSettingsRescan()
        })
        return view
    }

    private var rootLayout: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            reviewWorkspace
            Divider()
            footerBar
        }
        .frame(minWidth: isBatchReview ? 1180 : 980, minHeight: 680)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var toolbarButtonRow: some View {
        HStack(spacing: RedaktrUI.controlSpacing) {
            Button {
                openImage()
            } label: {
                Image(systemName: "folder")
                    .topToolbarControl(width: RedaktrUI.compactControlWidth)
            }
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel("Open images or folder")
            .accessibilityHint("Choose screenshots, images, or a folder from disk.")
            .accessibilityIdentifier("open-image-button")
            .buttonStyle(.plain)

            Button {
                activeToolbarPopover = activeToolbarPopover == .capture ? nil : .capture
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .topToolbarControl(width: RedaktrUI.splitControlWidth)
            }
            .disabled(isChecking || isCapturing)
            .help("Capture locally, then review in Redaktr")
            .accessibilityLabel("Capture")
            .accessibilityHint("Capture screen, window, or area and scan the temporary image locally.")
            .accessibilityIdentifier("capture-menu-button")
            .buttonStyle(.plain)
            .popover(isPresented: toolbarPopoverBinding(.capture)) {
                captureToolbarPopover
            }

            if isChecking {
                Button {
                    cancelDetection()
                } label: {
                    Image(systemName: "xmark.circle")
                        .topToolbarControl(width: RedaktrUI.compactControlWidth)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel detection")
                .accessibilityHint("Stop the current on-device detection run.")
                .accessibilityIdentifier("cancel-detection-button")
                .buttonStyle(.plain)
            } else {
                Button {
                    detectSensitiveText()
                } label: {
                    Label(redactionPlan.detections.isEmpty ? "Scan" : "Re-scan", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .topToolbarControl(width: 112)
                }
                .disabled(cgImage == nil)
                .keyboardShortcut("d", modifiers: .command)
                .accessibilityLabel("Detect sensitive content")
                .accessibilityHint("Find likely leaks in the loaded image on this Mac.")
                .accessibilityIdentifier("detect-button")
                .buttonStyle(.plain)
            }

            Button {
                clearCurrentReview()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .labelStyle(.titleAndIcon)
                    .topToolbarControl(width: 92)
            }
            .disabled(!canCloseCurrentReview || isChecking)
            .help(canCloseCurrentReview ? closeCurrentReviewLabel : "Open an image or batch before Clear is available.")
            .keyboardShortcut("w", modifiers: .command)
            .accessibilityLabel("Clear current review")
            .accessibilityHint("Discard the current image or batch and return to the start screen.")
            .accessibilityIdentifier("clear-current-review-button")
            .buttonStyle(.plain)

            Button {
                activeToolbarPopover = activeToolbarPopover == .more ? nil : .more
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .topToolbarControl(width: RedaktrUI.splitControlWidth)
            }
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("more-actions-menu-button")
            .buttonStyle(.plain)
            .popover(isPresented: toolbarPopoverBinding(.more)) {
                moreToolbarPopover
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func toolbarPopoverBinding(_ popover: ToolbarPopover) -> Binding<Bool> {
        Binding(
            get: { activeToolbarPopover == popover },
            set: { isPresented in
                if !isPresented, activeToolbarPopover == popover {
                    activeToolbarPopover = nil
                }
            }
        )
    }

    private var captureToolbarPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(RedaktrCaptureMode.allCases) { mode in
                Button {
                    activeToolbarPopover = nil
                    startCapture(mode)
                } label: {
                    Label(mode.commandTitle, systemImage: mode.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isChecking || isCapturing)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("capture-\(mode.rawValue)-menu-item")
            }
        }
        .padding(8)
        .frame(width: 220)
    }

    private var moreToolbarPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbarPopoverButton(
                title: "Paste Image",
                systemImage: "doc.on.clipboard",
                identifier: "paste-image-menu-item",
                isDisabled: isChecking
            ) {
                importClipboardImage()
            }

            toolbarPopoverButton(
                title: closeCurrentReviewLabel,
                systemImage: "xmark.circle",
                identifier: "close-current-review-menu-item",
                isDisabled: !canCloseCurrentReview
            ) {
                clearCurrentReview()
            }

            Divider()

            toolbarPopoverButton(
                title: "Reveal Last Export",
                systemImage: "folder",
                identifier: "reveal-last-export-menu-item",
                isDisabled: lastExportLocation == nil
            ) {
                revealLastExportInFinder()
            }

            Divider()

            toolbarPopoverButton(
                title: "Help Center",
                systemImage: "questionmark.circle",
                identifier: "help-center-menu-item"
            ) {
                presentHelpSheet(.helpCenter)
            }

            toolbarPopoverButton(
                title: "Settings",
                systemImage: "gearshape",
                identifier: "settings-menu-item",
                isDisabled: isChecking
            ) {
                openSettings()
            }
        }
        .padding(8)
        .frame(width: 230)
    }

    private func toolbarPopoverButton(
        title: String,
        systemImage: String,
        identifier: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            activeToolbarPopover = nil
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier(identifier)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: image == nil ? 0 : 9) {
                if image == nil {
                    RedaktrHeaderMark()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(sourceDisplayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sourceDisplayName)

            Spacer()

            toolbarButtonRow

            Divider()
                .frame(height: 24)

            scanStatusPill
        }
        .padding(.horizontal, RedaktrUI.panelPadding)
        .frame(height: 64)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var reviewWorkspace: some View {
        HStack(spacing: 0) {
            if isBatchReview {
                batchQueueSidebar
                    .frame(width: 260)

                Divider()
            }

            imageStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            reviewPanel
                .frame(width: 376)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var batchQueueSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Batch")
                    .font(.headline.weight(.bold))

                Text("\(batchCompletedScanCount) of \(batchItems.count) scanned - \(batchImagesWithFindingsCount) with findings - \(batchCleanImagesCount) clean")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Reviewed \(batchReviewedFindingImagesCount) of \(batchImagesWithFindingsCount) with findings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("batch-review-progress-label")

                if isBatchScanning {
                    ProgressView(value: Double(batchCompletedScanCount), total: Double(max(batchItems.count, 1)))
                        .accessibilityLabel("Batch scan progress")
                }
            }

            batchFilterControl

            if !batchFindingCategorySummaries.isEmpty {
                batchCategoryFilterControl
            }

            HStack(spacing: 8) {
                Button {
                    selectPreviousBatchImage()
                } label: {
                    Label("Prev", systemImage: "chevron.up")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(filteredBatchItems.count < 2)
                .keyboardShortcut(.upArrow, modifiers: [])
                .help("Select the previous image in the visible batch list.")
                .accessibilityIdentifier("previous-batch-image-button")

                Button {
                    selectNextBatchImage()
                } label: {
                    Label("Next", systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(filteredBatchItems.count < 2)
                .keyboardShortcut(.downArrow, modifiers: [])
                .help("Select the next image in the visible batch list.")
                .accessibilityIdentifier("next-batch-image-button")
            }
            .buttonStyle(.bordered)

            if filteredBatchItems.isEmpty {
                Text("No images match this filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("batch-empty-filter-state")
            } else {
                BatchQueueTable(
                    items: filteredBatchItems,
                    selectedID: selectedBatchItemID,
                    onSelect: selectBatchItem
                )
                .accessibilityIdentifier("batch-items-list")
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .onMoveCommand { direction in
            switch direction {
            case .up:
                selectPreviousBatchImage()
            case .down:
                selectNextBatchImage()
            default:
                break
            }
        }
        .accessibilityIdentifier("batch-queue-sidebar")
    }

    private var batchFilterControl: some View {
        HStack(spacing: 2) {
            ForEach(BatchReviewFilter.allCases) { filter in
                let isSelected = batchFilter == filter

                Button {
                    setBatchFilter(filter)
                } label: {
                    Text(filter.displayName)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color(nsColor: .textBackgroundColor) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("batch-filter-\(filter.rawValue)")
                .accessibilityLabel(filter.displayName)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("batch-filter-picker")
    }

    private var batchCategoryFilterControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finding type")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    batchCategoryFilterButton(title: "All", category: nil, findingCount: nil)

                    ForEach(batchFindingCategorySummaries, id: \.category) { summary in
                        batchCategoryFilterButton(
                            title: summary.category.displayName,
                            category: summary.category,
                            findingCount: summary.findingCount
                        )
                    }
                }
            }
            .help("Review a large folder by finding type, such as Secrets or Customer/account data.")

            if let batchCategoryFilter,
               let summary = batchFindingCategorySummaries.first(where: { $0.category == batchCategoryFilter }) {
                Text("\(summary.imageCount) images · \(summary.findingCount) findings")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("batch-category-filter-summary")
            } else {
                Text("Review by finding type across the folder.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("batch-category-filter-summary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("batch-category-filter-control")
    }

    private func batchCategoryFilterButton(
        title: String,
        category: FindingCategory?,
        findingCount: Int?
    ) -> some View {
        let isSelected = batchCategoryFilter == category

        return Button {
            setBatchCategoryFilter(category)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if let findingCount {
                    Text("\(findingCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.secondary.opacity(0.12)))
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlColor).opacity(0.55))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(category.map { "batch-category-filter-\($0.rawValue)" } ?? "batch-category-filter-all")
        .accessibilityLabel(category.map { "Filter batch by \($0.displayName)" } ?? "Show all finding types")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var imageStage: some View {
        ZStack(alignment: .bottomLeading) {
            Color(nsColor: .windowBackgroundColor)

            if let displayedImage {
                ImageReviewView(
                    image: displayedImage,
                    redactionPlan: $redactionPlan,
                    selectedDetectionID: $selectedDetectionID,
                    isManualEditing: $isManualEditing,
                    isPreviewingRedactedOutput: isPreviewingRedactedOutput,
                    keepsManualEditingAfterCommit: keepsManualEditingAfterCommit,
                    onPlanChanged: handlePlanChanged,
                    onManualEditCommitted: recordManualEdit
                )
                .padding(RedaktrUI.panelPadding)
            } else {
                DropTargetView(
                    onOpenImage: openImage,
                    onPasteImage: importClipboardImage,
                    onCaptureArea: { startCapture(.area) },
                    onOpenBatch: openImage
                )
                .padding(48)
            }

            if image != nil {
                previewToggle
                    .padding(RedaktrUI.panelPadding)
            }
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            if isPreviewingRedactedOutput {
                PreviewOutputBanner()
                    .accessibilityIdentifier("preview-output-banner")
                    .padding(RedaktrUI.panelPadding)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let completionBannerText {
                CompletionBanner(
                    text: completionBannerText,
                    actionTitle: completionBannerAction?.title,
                    action: completionBannerAction == nil ? nil : { performCompletionBannerAction(completionBannerAction) },
                    secondaryActionTitle: completionBannerSecondaryAction?.title,
                    secondaryAction: completionBannerSecondaryAction == nil ? nil : { performCompletionBannerAction(completionBannerSecondaryAction) }
                )
                    .padding(RedaktrUI.panelPadding)
            }
        }
    }

    private var previewToggle: some View {
        Toggle(isOn: Binding(get: { isPreviewingRedactedOutput }, set: setPreviewingRedactedOutput)) {
            Label("Preview redacted output", systemImage: "eye")
                .font(.callout.weight(.medium))
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.24), lineWidth: 1))
        .disabled(cgImage == nil)
        .keyboardShortcut("p", modifiers: .command)
        .accessibilityLabel("Preview redacted output")
        .accessibilityValue(isPreviewingRedactedOutput ? "On" : "Off")
        .accessibilityIdentifier("preview-redacted-output-toggle")
        .accessibilityHint("Shows the exact flattened image that copy and export will produce.")
    }

    private var scanStatusPill: some View {
        HStack(spacing: 8) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: scanStatusIcon)
                    .font(.callout.weight(.semibold))
            }

            Text(scanStatusText)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(scanStatusForeground)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(scanStatusBackground, in: Capsule())
        .accessibilityIdentifier("scan-status-pill")
    }

    @ViewBuilder
    private var ambientModeIndicators: some View {
        if clipboardProtectionController.isRunning {
            AmbientModePill(
                title: "Clipboard",
                systemImage: "doc.on.clipboard",
                accessibilityID: "clipboard-protection-active-pill",
                hint: "Clipboard image protection is active and scans image clipboard changes locally."
            )
        }

        if screenshotWatchController.isRunning {
            AmbientModePill(
                title: "Watching",
                systemImage: "folder.badge.gearshape",
                accessibilityID: "screenshot-watch-active-pill",
                hint: "Screenshot Watch is active and scans new images in the selected folder."
            )
        }
    }

    private var watchedScreenshotAlertsMenu: some View {
        Menu {
            ForEach(watchedScreenshotQueue.items) { item in
                Button {
                    openWatchedScreenshot(item.id)
                } label: {
                    Label(
                        "\(item.displayName) - \(item.findingCount) \(item.findingCount == 1 ? "finding" : "findings")",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }

            Divider()

            Button(role: .destructive) {
                watchedScreenshotQueue.removeAll()
            } label: {
                Label("Clear watched alerts", systemImage: "xmark.circle")
            }
        } label: {
            Label("Watched alerts \(watchedScreenshotQueue.count)", systemImage: "exclamationmark.folder")
                .font(.footnote.weight(.medium))
        }
        .help("Review watched screenshots with possible leaks. The active image is not changed until you choose one.")
        .accessibilityIdentifier("watched-alerts-menu")
        .accessibilityLabel("Watched alerts")
        .accessibilityValue("\(watchedScreenshotQueue.count)")
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 12) {
                    Text(redactionPlan.entries.isEmpty ? "Findings" : "\(redactionPlan.entries.count) possible leaks")
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("redaction-count-label")

                    Spacer()

                    if !redactionPlan.entries.isEmpty {
                        Text("\(redactionPlan.entries.count)")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.16), lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                }

                if isUITestMode {
                    Button(redactionCountSummary) {}
                        .buttonStyle(.plain)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .accessibilityIdentifier("redaction-count-value")
                        .accessibilityLabel(redactionCountSummary)

                    #if DEBUG
                    if isUITestMode {
                        Button(uiTestSampleStatus) {}
                            .buttonStyle(.plain)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .accessibilityIdentifier("ui-test-sample-status")
                            .accessibilityLabel(uiTestSampleStatus)
                    }
                    #endif
                }

                Text(reviewSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if isPreviewingRedactedOutput {
                    Label("Output preview", systemImage: "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .accessibilityIdentifier("preview-output-banner")
                }

                if let state = selectedItem?.scanState, state == .failed || state == .cancelled {
                    Button("I reviewed this image manually") {
                        confirmManualReview()
                    }
                    .accessibilityIdentifier("confirm-manual-review-button")
                    .help("Enable export with the current masks after inspecting the entire image yourself.")
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }

            if !redactionPlan.entries.isEmpty {
                findingFilterControl
            }

            if redactionPlan.entries.isEmpty {
                EmptyDetectionState(isChecking: isChecking, hasImage: image != nil)
            } else if filteredEntries.isEmpty {
                EmptyFilterState(filter: findingFilter)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(findingGroups) { group in
                            DetectionGroupSection(
                                group: group,
                                selectedDetectionID: selectedDetectionID,
                                activeBinding: activeBinding(for:),
                                onSelect: selectDetection,
                                onSetGroupActive: setEntriesActive,
                                onRememberSafe: rememberSafeFinding,
                                onSetDetectorDisposition: setDetectorDisposition,
                                onOpenDetectionSettings: openDetectionSettingsFromFinding
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
            }

            reviewControlStrip
        }
        .padding(RedaktrUI.panelPadding)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var reviewControlStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !redactionPlan.entries.isEmpty {
                Divider()
                findingActionControls
            }

            if image != nil {
                if redactionPlan.entries.isEmpty {
                    Divider()
                }
                manualEditorControls
            }
        }
    }

    private var findingActionControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: selectPreviousDetection) {
                    Label("Prev", systemImage: "chevron.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 76))
                .keyboardShortcut(.upArrow, modifiers: .command)
                .accessibilityIdentifier("previous-finding-button")

                Button(action: selectNextDetection) {
                    Label("Next", systemImage: "chevron.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 76))
                .keyboardShortcut(.downArrow, modifiers: .command)
                .accessibilityIdentifier("next-finding-button")

                Button(action: toggleSelectedDetection) {
                    Label("Toggle", systemImage: "checkmark.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.secondary, minWidth: 96))
                .disabled(selectedDetectionID == nil)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("toggle-selected-finding-button")
            }

            HStack(spacing: 8) {
                Button {
                    setAllActive(true)
                } label: {
                    Label("Redact", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 110))
                .accessibilityIdentifier("include-all-findings-button")

                Button {
                    setAllActive(false)
                } label: {
                    Label("Visible", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 110))
                .accessibilityIdentifier("exclude-all-findings-button")
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            Text("On-device - no account - detection can miss things - review before sharing")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("local-only-copy-text")

            ambientModeIndicators

            if !watchedScreenshotQueue.isEmpty {
                watchedScreenshotAlertsMenu
            }


            Spacer()

            if isBatchReview {
                Toggle("Include zero findings", isOn: $includesCleanBatchExports)
                    .toggleStyle(.checkbox)
                    .font(.footnote.weight(.medium))
                    .help("Include reviewed images and successful scans with no findings in the batch export.")
                    .accessibilityIdentifier("include-clean-batch-items-toggle")

                Button(action: exportBatchRedacted) {
                    Label("Export batch", systemImage: "square.and.arrow.up.on.square")
                }
                .buttonStyle(.redaktr(.primary, minWidth: 128))
                .disabled(!canShareBatch)
                .accessibilityLabel("Export cleaned batch")
                .accessibilityHint("Save flattened cleaned copies for the loaded batch.")
                .accessibilityIdentifier("export-batch-button")
            }


            Button(action: copyRedacted) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.redaktr(.secondary, minWidth: 96))
            .disabled(!canShareSelected)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel("Copy cleaned PNG")
            .accessibilityHint("Copy a flattened PNG with active redactions applied and metadata stripped.")
            .accessibilityIdentifier("copy-redacted-button")

            Button(action: exportRedacted) {
                Label("Export cleaned copy", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.redaktr(.primary, minWidth: 180))
            .disabled(!canShareSelected)
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityLabel("Export cleaned image")
            .accessibilityHint("Save a flattened cleaned copy with active redactions applied and metadata stripped.")
            .accessibilityIdentifier("export-redacted-button")
        }
        .padding(.horizontal, RedaktrUI.panelPadding)
        .frame(minHeight: 72)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var manualEditorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Manual", systemImage: "rectangle.dashed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { isManualEditing }, set: setManualEditing)) {
                    Label("Draw", systemImage: "plus.rectangle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(image == nil || isChecking)
                .help(image == nil ? "Open an image before drawing a manual redaction." : "Draw a new redaction box over content Redaktr missed.")
                .accessibilityLabel("Draw manual redaction")
                .accessibilityHint("Draw a new redaction box over content Redaktr missed.")
                .accessibilityIdentifier("manual-draw-toggle")

                Toggle(isOn: $keepsManualEditingAfterCommit) {
                    Label("Keep", systemImage: "pin")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(image == nil || isChecking)
                .help(image == nil ? "Open an image before using keep drawing." : "Keep Draw enabled after each manual box.")
                .accessibilityLabel("Keep drawing after adding a redaction")
                .accessibilityIdentifier("manual-sticky-draw-toggle")
            }

            HStack(spacing: 8) {
                Button(action: undoManualEdit) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 84))
                .keyboardShortcut("z", modifiers: .command)
                .disabled(isChecking || !manualEditHistory.canUndo)
                .help(manualEditHistory.canUndo ? "Undo the last manual change." : "Draw, move, reset, or delete a box before Undo is available.")
                .accessibilityLabel("Undo manual edit")
                .accessibilityIdentifier("undo-manual-edit-button")

                Button(action: redoManualEdit) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 84))
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(isChecking || !manualEditHistory.canRedo)
                .help(manualEditHistory.canRedo ? "Redo the last undone manual change." : "Use Undo before Redo is available.")
                .accessibilityLabel("Redo manual edit")
                .accessibilityIdentifier("redo-manual-edit-button")
            }

            HStack(spacing: 8) {
                Button(action: resetSelectedBounds) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.quiet, minWidth: 84))
                .disabled(selectedAdjustedRedactionID == nil || isChecking)
                .help(selectedAdjustedRedactionID == nil ? "Select a moved or resized box to reset its bounds." : "Restore the selected box to its original detected bounds.")
                .accessibilityLabel("Reset selected bounds")
                .accessibilityIdentifier("reset-selected-bounds-button")

                Button(role: .destructive, action: deleteSelectedManualRedaction) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.redaktr(.destructive, minWidth: 84))
                .disabled(selectedManualRedactionID == nil || isChecking)
                .help(selectedManualRedactionID == nil ? "Select a manual box you drew to delete it." : "Delete the selected manual redaction box.")
                .accessibilityLabel("Delete selected manual redaction")
                .accessibilityIdentifier("delete-selected-manual-redaction-button")
            }
        }
    }

    private var findingFilterControl: some View {
        HStack(spacing: 2) {
            ForEach(FindingFilter.allCases) { filter in
                let isSelected = findingFilter == filter

                Button {
                    setFindingFilter(filter)
                } label: {
                    Text(filter.displayName)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color(nsColor: .textBackgroundColor) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("findings-filter-\(filter.rawValue)")
                .accessibilityLabel(filter.displayName)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .help("Check needs inspection. Redact will be hidden. Visible stays in the cleaned output.")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findings-filter-picker")
    }

    private func activeBinding(for id: Detection.ID) -> Binding<Bool> {
        Binding(
            get: {
                redactionPlan.entries.first { $0.id == id }?.isActive ?? false
            },
            set: { isActive in
                redactionPlan.setActive(isActive, for: id)
                handlePlanChanged()
            }
        )
    }

    private func selectDetection(_ id: Detection.ID) {
        guard redactionPlan.entries.contains(where: { $0.id == id }) else { return }
        selectedDetectionID = id
        isManualEditing = false
        updateReviewStatus()
    }

    private func setEntriesActive(_ isActive: Bool, for ids: [Detection.ID]) {
        for id in ids {
            redactionPlan.setActive(isActive, for: id)
        }
        handlePlanChanged()
    }

    private func setAllActive(_ isActive: Bool) {
        for entry in redactionPlan.entries {
            redactionPlan.setActive(isActive, for: entry.id)
        }
        handlePlanChanged()
    }

    private func selectPreviousDetection() {
        selectDetection(offset: -1)
    }

    private func selectNextDetection() {
        selectDetection(offset: 1)
    }

    private func selectDetection(offset: Int) {
        guard !redactionPlan.entries.isEmpty else { return }

        let currentIndex = selectedDetectionID.flatMap { selectedID in
            redactionPlan.entries.firstIndex { $0.id == selectedID }
        } ?? (offset > 0 ? -1 : redactionPlan.entries.count)
        let nextIndex = (currentIndex + offset + redactionPlan.entries.count) % redactionPlan.entries.count
        selectDetection(redactionPlan.entries[nextIndex].id)
    }

    private func selectPreviousBatchImage() {
        selectBatchImage(offset: -1)
    }

    private func selectNextBatchImage() {
        selectBatchImage(offset: 1)
    }

    private func selectBatchImage(offset: Int) {
        guard filteredBatchItems.count > 1 else { return }

        let currentIndex = selectedBatchItemID.flatMap { selectedID in
            filteredBatchItems.firstIndex { $0.id == selectedID }
        } ?? (offset > 0 ? -1 : filteredBatchItems.count)
        let nextIndex = (currentIndex + offset + filteredBatchItems.count) % filteredBatchItems.count
        selectBatchItem(filteredBatchItems[nextIndex].id)
    }

    private func toggleSelectedDetection() {
        guard let selectedEntry else { return }

        redactionPlan.setActive(!selectedEntry.isActive, for: selectedEntry.id)
        handlePlanChanged()
    }

    private func rememberSafeFinding(_ entry: RedactionPlanEntry) {
        guard let matchedText = entry.detection.matchedText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !matchedText.isEmpty
        else {
            return
        }

        let existingEntries = allowlistText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedExisting = Set(existingEntries.map { $0.lowercased() })
        if !normalizedExisting.contains(matchedText.lowercased()) {
            allowlistText = (existingEntries + [matchedText]).joined(separator: "\n")
        }

        redactionPlan.setActive(false, for: entry.id)
        reviewStatusNote = "Marked visible and remembered the exact matched text as safe locally."
        handlePlanChanged()
    }

    private func setDetectorDisposition(
        _ disposition: RedactionPolicyDisposition,
        for entry: RedactionPlanEntry
    ) {
        var preferences = RedaktrSettingsStorage.detectorCategoryPreferences(from: detectorCategoryPreferencesData)
        preferences.setDisposition(disposition, forDetectorLabel: entry.detection.label)
        detectorCategoryPreferencesData = RedaktrSettingsStorage.detectorCategoryPreferencesData(preferences)
        reviewStatusNote = "\(entry.detection.label) set to \(disposition.displayName). Current image will re-scan."
        scheduleCustomSettingsRescan()
    }

    private func openDetectionSettingsFromFinding() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .redaktrOpenDetectionSettings, object: nil)
        }
    }

    private func setFindingFilter(_ filter: FindingFilter) {
        findingFilter = filter
        if let selectedDetectionID, !filteredEntries.contains(where: { $0.id == selectedDetectionID }) {
            self.selectedDetectionID = nil
        }
        updateReviewStatus()
    }

    private func setBatchFilter(_ filter: BatchReviewFilter) {
        batchFilter = filter
        if filter == .clean {
            batchCategoryFilter = nil
        }

        selectFirstFilteredBatchItemIfNeeded()
    }

    private func setBatchCategoryFilter(_ category: FindingCategory?) {
        batchCategoryFilter = category
        if category != nil, batchFilter == .clean {
            batchFilter = .findings
        }

        selectFirstFilteredBatchItemIfNeeded()
    }

    private func selectFirstFilteredBatchItemIfNeeded() {
        guard !filteredBatchItems.isEmpty else { return }

        if let selectedBatchItemID,
           filteredBatchItems.contains(where: { $0.id == selectedBatchItemID }) {
            return
        }

        selectBatchItem(filteredBatchItems[0].id)
    }

    private func setPreviewingRedactedOutput(_ isPreviewing: Bool) {
        guard cgImage != nil else {
            isPreviewingRedactedOutput = false
            redactedPreviewImage = nil
            return
        }

        isPreviewingRedactedOutput = isPreviewing
        isManualEditing = false

        if isPreviewing {
            refreshRedactedPreview()
            reviewStatusNote = "Previewing the exact flattened output for copy and export."
        } else {
            updateReviewStatus()
        }
    }

    private func refreshRedactedPreviewIfNeeded() {
        guard isPreviewingRedactedOutput else { return }
        refreshRedactedPreview()
    }

    private func refreshRedactedPreview() {
        guard let cgImage else {
            redactedPreviewImage = nil
            return
        }

        do {
            let previewCGImage = try renderer.renderImage(redacting: redactionPlan.activeDetections, in: cgImage)
            redactedPreviewImage = Self.previewImage(from: previewCGImage)
        } catch {
            redactedPreviewImage = nil
            errorText = "Preview failed. Try copy or export again."
            reviewStatusNote = "Output preview could not be generated."
        }
    }

    private func handlePlanChanged() {
        clearMissingSelection()
        updateReviewStatus()
        refreshRedactedPreviewIfNeeded()
        syncCurrentStateToBatchItem()
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageImporter.supportedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Open"

        guard panel.runModal() == .OK else { return }
        loadImageInputs(from: panel.urls)
    }

    private func importClipboardImage() {
        guard !isChecking else { return }
        errorText = nil

        guard let data = clipboardImageData() else {
            errorText = "Clipboard does not contain an image Redaktr can open."
            reviewStatusNote = "Copy an image, then use Paste Image."
            return
        }

        loadImage(
            from: data,
            sourceURL: nil,
            sourceLabel: "Clipboard image",
            sourceType: .clipboardImport,
            status: "Clipboard image loaded. Scanning on device..."
        )
    }

    private func handleCaptureRequestNotification(_ notification: NotificationCenter.Publisher.Output) {
        guard let mode = notification.object as? RedaktrCaptureMode else { return }
        startCapture(mode)
    }

    private func startCapture(_ mode: RedaktrCaptureMode) {
        guard captureTask == nil, !isChecking else { return }

        errorText = nil
        isManualEditing = false
        isPreviewingRedactedOutput = false
        redactedPreviewImage = nil
        activeCaptureMode = mode
        reviewStatusNote = mode.preparationMessage

        let configuration = customDetectionConfiguration
        captureTask = Task {
            do {
                let outputURL = try await captureService.capture(mode)
                let data = try Data(contentsOf: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
                try Task.checkCancellation()
                let importedImage = try ImageImporter.importImage(from: data)
                let detector = SensitiveTextDetector(customConfiguration: configuration)
                let plan = try await redactionPlan(
                    for: importedImage.cgImage,
                    orientation: importedImage.orientation,
                    detector: detector,
                    manualDetections: [],
                    manualActiveStates: [:]
                )
                try Task.checkCancellation()

                await MainActor.run {
                    captureTask = nil
                    activeCaptureMode = nil
                    handleCapturedImage(
                        importedImage,
                        plan: plan,
                        mode: mode
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    captureTask = nil
                    activeCaptureMode = nil
                    reviewStatusNote = "Capture canceled. Choose another source when ready."
                }
            } catch RedaktrCaptureError.canceled {
                await MainActor.run {
                    captureTask = nil
                    activeCaptureMode = nil
                    reviewStatusNote = "Capture canceled. No image was imported."
                }
            } catch RedaktrCaptureError.permissionDenied {
                await MainActor.run {
                    captureTask = nil
                    activeCaptureMode = nil
                    errorText = "Allow Screen Recording permission for Redaktr in macOS Privacy settings, then try capture again."
                    reviewStatusNote = RedaktrCaptureMode.permissionExplanation
                    revealMainWindowAfterCapture()
                }
            } catch {
                await MainActor.run {
                    captureTask = nil
                    activeCaptureMode = nil
                    errorText = "Capture failed. Try another capture mode or import an image."
                    reviewStatusNote = RedaktrCaptureMode.permissionExplanation
                    revealMainWindowAfterCapture()
                }
            }
        }
    }

    private func handleCapturedImage(
        _ importedImage: ImportedImage,
        plan: RedactionPlan,
        mode: RedaktrCaptureMode
    ) {
        let policy = RedaktrCaptureOutputSettingsStorage.policy
        let decision = autoCleanCoordinator.captureDecision(for: plan, policy: policy)

        guard !decision.shouldReviewInRedaktr else {
            openCapturedImageForReview(
                importedImage,
                plan: plan,
                mode: mode,
                status: captureReviewStatus(for: decision, mode: mode)
            )
            revealMainWindowAfterCapture()
            return
        }

        do {
            try performCaptureAutoOutput(
                importedImage,
                plan: plan,
                mode: mode,
                outputMode: decision.mode
            )
        } catch CaptureAutoOutputError.missingSaveFolder {
            openCapturedImageForReview(
                importedImage,
                plan: plan,
                mode: mode,
                status: "Capture scanned locally. Choose a capture output folder in Settings to use save modes."
            )
            errorText = "Capture save mode needs an output folder in Settings."
            revealMainWindowAfterCapture()
        } catch {
            openCapturedImageForReview(
                importedImage,
                plan: plan,
                mode: mode,
                status: "Capture scanned locally. Auto-output failed, so Redaktr opened review."
            )
            errorText = "Capture auto-output failed. Review and copy or export manually."
            revealMainWindowAfterCapture()
        }
    }

    private func captureReviewStatus(
        for decision: RedaktrCaptureOutputDecision,
        mode: RedaktrCaptureMode
    ) -> String {
        switch decision.fallbackReason {
        case .explicitReviewMode:
            return "\(mode.reviewSourceLabel) loaded. Review the findings, then copy or export a cleaned image."
        case .reviewFirstMode:
            return "\(mode.reviewSourceLabel) opened for review because AutoClean is set to Review first."
        case .reviewFindingsPresent(let count):
            return "\(mode.reviewSourceLabel) has \(count) \(count == 1 ? "finding" : "findings") needing Check, so auto-output paused for review."
        case nil:
            return "\(mode.reviewSourceLabel) loaded. Review the findings, then copy or export a cleaned image."
        }
    }

    private func openCapturedImageForReview(
        _ importedImage: ImportedImage,
        plan: RedactionPlan,
        mode: RedaktrCaptureMode,
        status: String
    ) {
        let item = BatchReviewItem(
            sourceURL: nil,
            sourceLabel: mode.reviewSourceLabel,
            sourceType: .capture,
            importedImage: importedImage,
            redactionPlan: plan,
            selectedDetectionID: plan.entries.first?.id,
            reviewStatusNote: status,
            scanState: .succeeded
        )
        replaceBatchItems([item], status: status, autoDetect: false)
        selectedDetectionID = plan.entries.first?.id
        recordSafeShareHistory(sourceType: .capture, action: .scan, plan: plan)
    }

    private func makeCapturedReviewItem(
        _ importedImage: ImportedImage,
        plan: RedactionPlan,
        mode: RedaktrCaptureMode,
        status: String
    ) -> BatchReviewItem {
        BatchReviewItem(
            sourceURL: nil,
            sourceLabel: mode.reviewSourceLabel,
            sourceType: .capture,
            importedImage: importedImage,
            redactionPlan: plan,
            selectedDetectionID: plan.entries.first?.id,
            reviewStatusNote: status,
            scanState: .succeeded
        )
    }

    private func performCaptureAutoOutput(
        _ importedImage: ImportedImage,
        plan: RedactionPlan,
        mode: RedaktrCaptureMode,
        outputMode: RedaktrCaptureOutputMode
    ) throws {
        let data = try renderer.renderPNG(redacting: plan.activeDetections, in: importedImage.cgImage)
        var outputURL: URL?
        let previousClipboard = outputMode.copiesToClipboard
            ? ClipboardUndoSnapshot.capture(from: RedaktrPasteboard.current)
            : nil

        if outputMode.savesToFolder {
            outputURL = try writeCaptureOutputPNG(data, mode: mode)
        }

        var writtenGeneration: Int?
        if let previousClipboard {
            do {
                guard let generation = try previousClipboard.replace(with: data, in: RedaktrPasteboard.current) else {
                    throw RedaktrCoreError.imageDestinationFailed
                }
                writtenGeneration = generation
                clipboardProtectionController.markHandled(changeCount: generation)
            } catch {
                guard outputURL != nil else { throw error }
                // The requested folder output succeeded. Report that output explicitly.
            }
        }
        let completedMode: RedaktrCaptureOutputMode = outputURL != nil && writtenGeneration == nil
            ? .saveCleanedPNG : outputMode

        let status = completedMode == outputMode
            ? captureAutoOutputStatus(mode: completedMode, outputURL: outputURL)
            : "Capture saved. The clipboard could not be updated."
        reviewStatusNote = status
        errorText = nil
        if let outputURL {
            lastExportLocation = ExportLocation(url: outputURL, isDirectory: false)
        }
        lastAutoCleanReviewItem = makeCapturedReviewItem(
            importedImage,
            plan: plan,
            mode: mode,
            status: "AutoClean produced a cleaned PNG. Review the boxes before sharing sensitive screenshots."
        )
        autoCleanUndoCoordinator.retain(
            autoCleanCoordinator.undoToken(
                clipboardSnapshot: previousClipboard,
                generatedFileURL: outputURL,
                writtenClipboardChangeCount: writtenGeneration
            )
        )
        presentAutoCleanReceipt(autoCleanCoordinator.captureReceipt(
            title: completedMode == outputMode ? captureAutoOutputCompletion(mode: completedMode) : "Saved PNG; clipboard unavailable",
            plan: plan
        ))
        recordSafeShareHistory(
            sourceType: .capture,
            action: outputMode.savesToFolder ? .exportCleanedImage : .copyCleanedPNG,
            plan: plan,
            outputPath: outputURL?.path
        )
    }

    private func writeCaptureOutputPNG(_ data: Data, mode: RedaktrCaptureMode) throws -> URL {
        guard let folder = try RedaktrCaptureOutputSettingsStorage.resolveFolder()?.url else {
            throw CaptureAutoOutputError.missingSaveFolder
        }

        let didAccess = folder.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outputURL = Self.uniqueCaptureOutputURL(in: folder, mode: mode, date: Date())
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func captureAutoOutputStatus(
        mode: RedaktrCaptureOutputMode,
        outputURL: URL?
    ) -> String {
        switch mode {
        case .copyCleanedPNG:
            return "Capture scanned locally. Cleaned PNG copied to clipboard."
        case .saveCleanedPNG:
            return "Capture scanned locally. Cleaned PNG saved to \(outputURL?.lastPathComponent ?? "the selected folder")."
        case .saveAndCopyCleanedPNG:
            return "Capture scanned locally. Cleaned PNG saved and copied to clipboard."
        case .reviewInRedaktr:
            return "Capture opened for review."
        }
    }

    private func captureAutoOutputCompletion(mode: RedaktrCaptureOutputMode) -> String {
        switch mode {
        case .copyCleanedPNG:
            return "Cleaned screenshot copied"
        case .saveCleanedPNG:
            return "Cleaned screenshot saved"
        case .saveAndCopyCleanedPNG:
            return "Cleaned screenshot saved and copied"
        case .reviewInRedaktr:
            return "Review needed"
        }
    }

    private func revealMainWindowAfterCapture() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            focusMainWindowIfAvailable()
        }
    }

    private func refreshClipboardProtection() {
        clipboardMonitorGeneration = UUID()
        for task in clipboardProtectionScanTasks.values { task.cancel() }
        clipboardProtectionScanTasks.removeAll()
        clipboardProtectionController.refreshFromStoredSettings(isUITestMode: isUITestMode) { candidate in
            handleClipboardProtectionCandidate(candidate)
        }
    }

    private func handleClipboardProtectionCandidate(_ candidate: ClipboardImageCandidate) {
        guard clipboardProtectionScanTasks[candidate.changeCount] == nil else { return }

        let configuration = customDetectionConfiguration
        let generation = clipboardMonitorGeneration
        clipboardProtectionScanTasks[candidate.changeCount] = Task {
            do {
                let importedImage = try ImageImporter.importImage(from: candidate.data)
                let detector = SensitiveTextDetector(customConfiguration: configuration)
                let plan = try await redactionPlan(
                    for: importedImage.cgImage,
                    orientation: importedImage.orientation,
                    detector: detector,
                    manualDetections: [],
                    manualActiveStates: [:]
                )
                try Task.checkCancellation()

                await MainActor.run {
                    guard generation == clipboardMonitorGeneration else { return }
                    clipboardProtectionScanTasks[candidate.changeCount] = nil
                    guard configuration == customDetectionConfiguration else { return }
                    handleClipboardProtectionScanResult(
                        plan,
                        importedImage: importedImage,
                        candidate: candidate
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generation == clipboardMonitorGeneration else { return }
                    clipboardProtectionScanTasks[candidate.changeCount] = nil
                }
            } catch {
                await MainActor.run {
                    guard generation == clipboardMonitorGeneration else { return }
                    clipboardProtectionScanTasks[candidate.changeCount] = nil
                    if image == nil {
                        reviewStatusNote = "A clipboard image could not be opened. Clipboard contents were not changed."
                    }
                }
            }
        }
    }

    private func handleClipboardProtectionScanResult(
        _ plan: RedactionPlan,
        importedImage: ImportedImage,
        candidate: ClipboardImageCandidate
    ) {
        guard clipboardProtectionController.isRunning,
              RedaktrPasteboard.current.changeCount == candidate.changeCount else { return }
        guard !plan.entries.isEmpty else {
            recordSafeShareHistory(
                sourceType: .clipboardProtection,
                action: .scan,
                plan: plan
            )
            if image == nil {
                reviewStatusNote = "Clipboard image scanned. No obvious sensitive content found."
            }
            return
        }

        let status = "Clipboard image scanned. Review findings before pasting; clipboard contents were not changed."
        let item = BatchReviewItem(
            sourceURL: nil,
            sourceLabel: "Clipboard image",
            sourceType: .clipboardProtection,
            importedImage: importedImage,
            redactionPlan: plan,
            selectedDetectionID: plan.entries.first?.id,
            reviewStatusNote: status,
            scanState: .succeeded
        )
        recordSafeShareHistory(sourceType: .clipboardProtection, action: .scan, plan: plan)

        let decision = autoCleanCoordinator.clipboardDecision(
            for: plan,
            replacementMode: ClipboardProtectionSettingsStorage.replacementMode
        )

        if decision.shouldReviewInRedaktr {
            openClipboardImageForReview(item, decision: decision)
            return
        }

        replaceClipboardWithRedactedPNG(
            redactionPlan: plan,
            cgImage: importedImage.cgImage,
            originalChangeCount: candidate.changeCount,
            reviewItem: item
        )
    }

    private func openClipboardImageForReview(_ item: BatchReviewItem, decision: RedaktrCaptureOutputDecision) {
        let status: String
        switch decision.fallbackReason {
        case .explicitReviewMode, .reviewFirstMode:
            status = "Clipboard image opened for review before Redaktr changes the clipboard."
        case .reviewFindingsPresent(let count):
            status = "Clipboard image has \(count) \(count == 1 ? "finding" : "findings") needing Check, so AutoClean paused for review."
        case nil:
            status = item.reviewStatusNote
        }
        var reviewItem = item
        reviewItem.reviewStatusNote = status
        replaceBatchItems([reviewItem], status: status, autoDetect: false)
        selectedDetectionID = reviewItem.selectedDetectionID ?? reviewItem.redactionPlan.entries.first?.id
        lastAutoCleanReviewItem = reviewItem
    }

    private func replaceClipboardWithRedactedPNG(
        redactionPlan: RedactionPlan,
        cgImage: CGImage,
        originalChangeCount: Int,
        reviewItem: BatchReviewItem? = nil
    ) {

        do {
            let data = try renderer.renderPNG(redacting: redactionPlan.activeDetections, in: cgImage)
            let pasteboard = RedaktrPasteboard.current
            let previousClipboard = ClipboardUndoSnapshot.capture(from: pasteboard)
            guard previousClipboard.changeCount == originalChangeCount,
                  let generation = try previousClipboard.replace(with: data, in: pasteboard) else { return }
            clipboardProtectionController.markHandled(changeCount: generation)
            reviewStatusNote = "Clipboard replaced with a flattened cleaned PNG. Review before pasting into sensitive destinations."
            if let reviewItem {
                lastAutoCleanReviewItem = reviewItem
            }
            autoCleanUndoCoordinator.retain(
                autoCleanCoordinator.undoToken(
                    clipboardSnapshot: previousClipboard,
                    generatedFileURL: nil,
                    writtenClipboardChangeCount: generation
                )
            )
            presentAutoCleanReceipt(autoCleanCoordinator.clipboardReceipt(plan: redactionPlan))
            recordSafeShareHistory(action: .clipboardReplace, plan: redactionPlan)
            syncCurrentStateToBatchItem()
        } catch {
            errorText = "Clipboard replacement failed. Review the image and try Copy instead."
            reviewStatusNote = "Check the clipboard before pasting."
        }
    }

    private func refreshScreenshotWatch() {
        screenshotWatchController.refreshFromStoredSettings(isUITestMode: isUITestMode) { urls in
            handleWatchedScreenshotCandidates(urls)
        }
    }

    private func handleWatchedScreenshotCandidates(_ urls: [URL]) {
        for url in urls {
            scanWatchedScreenshot(url)
        }
    }

    private func scanWatchedScreenshot(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard watchedScreenshotScanTasks[path] == nil else { return }

        let configuration = customDetectionConfiguration
        watchedScreenshotScanTasks[path] = Task {
            do {
                let importedImage = try ImageImporter.importImage(from: url)
                let detector = SensitiveTextDetector(customConfiguration: configuration)
                let plan = try await redactionPlan(
                    for: importedImage.cgImage,
                    orientation: importedImage.orientation,
                    detector: detector,
                    manualDetections: [],
                    manualActiveStates: [:]
                )
                try Task.checkCancellation()

                await MainActor.run {
                    watchedScreenshotScanTasks[path] = nil
                    handleWatchedScreenshotScanResult(
                        plan,
                        importedImage: importedImage,
                        sourceURL: url
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    watchedScreenshotScanTasks[path] = nil
                }
            } catch {
                await MainActor.run {
                    watchedScreenshotScanTasks[path] = nil
                    if image == nil {
                        reviewStatusNote = "A watched screenshot could not be opened. Source files were not changed."
                    }
                }
            }
        }
    }

    private func handleWatchedScreenshotScanResult(
        _ plan: RedactionPlan,
        importedImage: ImportedImage,
        sourceURL: URL
    ) {
        guard !plan.entries.isEmpty else {
            recordSafeShareHistory(
                sourceType: .screenshotWatch,
                action: .scan,
                plan: plan
            )
            return
        }

        let status = "Watched screenshot scanned. Review findings before sharing. The source file was not changed."
        let item = BatchReviewItem(
            sourceURL: sourceURL,
            sourceType: .screenshotWatch,
            importedImage: importedImage,
            redactionPlan: plan,
            selectedDetectionID: plan.entries.first?.id,
            reviewStatusNote: status,
            scanState: .succeeded
        )
        enqueueWatchedScreenshot(item)
        recordSafeShareHistory(sourceType: .screenshotWatch, action: .scan, plan: plan)
        if !isUITestMode,
           RedaktrAutoCleanReceiptRouter.route(isAppActive: NSApp.isActive) == .systemNotification {
            ScreenshotWatchRiskNotifier.notify(
                fileName: sourceURL.lastPathComponent,
                findingCount: plan.entries.count
            )
        }
    }

    private func enqueueWatchedScreenshot(_ item: BatchReviewItem) {
        watchedScreenshotQueue.enqueue(item) { queuedItem in
            queuedItem.sourceURL?.standardizedFileURL == item.sourceURL?.standardizedFileURL
        }

        if image == nil && batchItems.isEmpty {
            reviewStatusNote = "Watched screenshot found \(item.findingCount) possible \(item.findingCount == 1 ? "leak" : "leaks"). Open Watched alerts to review."
        } else {
            showCompletion("Watched screenshot queued", action: .reviewLatestWatchedScreenshot)
        }
    }

    private func openLatestWatchedScreenshot() {
        guard let item = watchedScreenshotQueue.first else {
            showMainWindowForNotification()
            return
        }
        openWatchedScreenshot(item.id)
    }

    private func openWatchedScreenshot(_ id: BatchReviewItem.ID) {
        guard let index = watchedScreenshotQueue.firstIndex(where: { $0.id == id }) else {
            showMainWindowForNotification()
            return
        }

        let item = watchedScreenshotQueue.remove(at: index)
        replaceBatchItems([item], status: item.reviewStatusNote, autoDetect: false)
        selectedDetectionID = item.selectedDetectionID ?? item.redactionPlan.entries.first?.id
        revealMainWindowAfterCapture()
    }

    private func showMainWindowForNotification() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            focusMainWindowIfAvailable()
        }
    }

    private func loadLaunchFixtureIfNeeded() {
        guard !didLoadLaunchFixture else { return }
        didLoadLaunchFixture = true

        guard isUITestMode else { return }

        if let batchFixturePaths = ProcessInfo.processInfo.environment["REDAKTR_UI_BATCH_FIXTURE_PATHS"],
           !batchFixturePaths.isEmpty {
            let fixtureURLs = batchFixturePaths
                .components(separatedBy: CharacterSet(charactersIn: "\n\t"))
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            let seedsDetections = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_DETECTIONS"] == "1"
            loadImageInputs(
                from: fixtureURLs,
                status: "Fixture batch loaded. Review every image, then export cleaned copies.",
                autoDetect: !seedsDetections
            )
            seedUITestDetectionsIfNeeded()
            seedUITestWatchedScreenshotIfNeeded()
            return
        }

        guard
            let fixturePath = ProcessInfo.processInfo.environment["REDAKTR_UI_FIXTURE_PATH"],
            !fixturePath.isEmpty
        else {
            return
        }

        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let seedsDetections = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_DETECTIONS"] == "1"
        guard loadImage(
            from: fixtureURL,
            status: "Fixture image loaded. Review every box, then export a cleaned copy.",
            autoDetect: !seedsDetections
        ) else {
            return
        }

        seedUITestDetectionsIfNeeded()
        seedUITestWatchedScreenshotIfNeeded()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        if !fileProviders.isEmpty {
            loadDroppedFileURLs(from: fileProviders)
            return true
        }

        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                Task { @MainActor in
                    if let url = item as? URL {
                        loadImageInputs(from: [url])
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        loadImageInputs(from: [url])
                    } else {
                        failImageLoad(RedaktrCoreError.invalidImageData)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in
                    if let data {
                        loadImage(from: data, sourceType: .fileImport)
                    } else {
                        failImageLoad(RedaktrCoreError.invalidImageData)
                    }
                }
            }
            return true
        }

        return false
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if urls.isEmpty {
                failImageLoad(RedaktrCoreError.invalidImageData)
            } else {
                loadImageInputs(from: urls)
            }
        }
    }

    private func loadImageInputs(
        from urls: [URL],
        status: String = "Image loaded. Scanning on device...",
        autoDetect: Bool = true
    ) {
        let imageURLs: [URL]
        do {
            imageURLs = try supportedImageURLs(from: urls)
        } catch {
            showBatchLimit()
            return
        }
        guard !imageURLs.isEmpty else {
            failImageLoad(RedaktrCoreError.unsupportedImageType)
            return
        }

        var items: [BatchReviewItem] = []
        var failedImportCount = 0
        var budget = ImageBatchBudget()

        for url in imageURLs {
            do {
                let importedImage = imageURLs.count > 1
                    ? try ImageImporter.importImage(from: url, batchBudget: &budget)
                    : try ImageImporter.importImage(from: url)
                items.append(BatchReviewItem(
                    sourceURL: url,
                    sourceType: imageURLs.count > 1 ? .folderBatch : .fileImport,
                    importedImage: importedImage,
                    reviewStatusNote: imageURLs.count > 1 ? "Queued for on-device scan." : status
                ))
            } catch is ImageBatchLimitExceeded {
                showBatchLimit()
                return
            } catch {
                failedImportCount += 1
            }
        }

        guard !items.isEmpty else {
            failImageLoad(RedaktrCoreError.invalidImageData)
            return
        }

        replaceBatchItems(
            items,
            status: items.count > 1
                ? "\(items.count) images loaded. Scanning batch on device..."
                : status,
            failedImportCount: failedImportCount,
            autoDetect: autoDetect
        )
    }

    private func showBatchLimit() {
        errorText = "Choose a smaller batch (up to 128 images and 64 megapixels total), or open a large image on its own."
    }

    private func supportedImageURLs(from urls: [URL]) throws -> [URL] {
        var seenPaths = Set<String>()
        var imageURLs: [URL] = []

        func appendIfSupported(_ url: URL) throws {
            guard ImageImporter.isSupportedImageURL(url) else { return }
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { return }
            guard imageURLs.count < ImageBatchBudget.maximumFileCount else { throw ImageBatchLimitExceeded() }
            imageURLs.append(url)
        }

        for url in urls {
            guard Self.isDirectory(url) else {
                try appendIfSupported(url)
                continue
            }
            guard let files = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            let start = imageURLs.endIndex
            for case let entry as URL in files {
                guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                try appendIfSupported(entry)
            }
            imageURLs[start...].sort {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        }
        return imageURLs
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func replaceBatchItems(
        _ items: [BatchReviewItem],
        status: String,
        failedImportCount: Int = 0,
        autoDetect: Bool
    ) {
        invalidateBatchScan()
        customSettingsRescanTask?.cancel()
        customSettingsRescanTask = nil
        completionBannerText = nil
        completionBannerAction = nil
        completionBannerTask?.cancel()
        completionBannerTask = nil
        includesCleanBatchExports = true
        batchFilter = .all
        batchItems = items
        selectedBatchItemID = items.first?.id

        if let first = items.first {
            restoreBatchItem(first)
            reviewStatusNote = status
            if failedImportCount > 0 {
                errorText = "\(failedImportCount) image files could not be opened and were skipped."
            }
            syncCurrentStateToBatchItem()
        }

        if autoDetect {
            startBatchDetection(for: items.map(\.id))
        }
    }

    private func selectBatchItem(_ id: BatchReviewItem.ID) {
        guard selectedBatchItemID != id else {
            markBatchItemReviewed(id)
            return
        }

        syncCurrentStateToBatchItem()

        guard let item = batchItems.first(where: { $0.id == id }) else { return }
        restoreBatchItem(item)
        markBatchItemReviewed(id)
    }

    private func restoreBatchItem(_ item: BatchReviewItem) {
        selectedBatchItemID = item.id
        sourceImageURL = item.sourceURL
        sourceDisplayLabel = item.sourceLabel
        image = Self.previewImage(from: item.importedImage.cgImage)
        cgImage = item.importedImage.cgImage
        imageOrientation = item.importedImage.orientation
        redactionPlan = item.redactionPlan
        selectedDetectionID = item.selectedDetectionID
        manualEditHistory = item.manualEditHistory
        errorText = item.errorText
        reviewStatusNote = item.reviewStatusNote
        isManualEditing = false
        isPreviewingRedactedOutput = false
        redactedPreviewImage = nil
        clearMissingSelection()
        markBatchItemReviewed(item.id)
    }

    private func syncCurrentStateToBatchItem() {
        guard
            let selectedBatchItemID,
            let index = batchItems.firstIndex(where: { $0.id == selectedBatchItemID })
        else {
            return
        }

        batchItems[index].redactionPlan = redactionPlan
        batchItems[index].selectedDetectionID = selectedDetectionID
        batchItems[index].manualEditHistory = manualEditHistory
        batchItems[index].reviewStatusNote = reviewStatusNote
        batchItems[index].errorText = errorText
    }

    private func markBatchItemReviewed(_ id: BatchReviewItem.ID) {
        guard let index = batchItems.firstIndex(where: { $0.id == id }),
              batchItems[index].didScan,
              !batchItems[index].redactionPlan.entries.isEmpty
        else {
            return
        }

        batchItems[index].didReviewInBatch = true
    }

    private func focusBatchReviewAfterScanIfNeeded() {
        guard isBatchReview, batchImagesWithFindingsCount > 0 else { return }

        if batchFilter == .all {
            batchFilter = .findings
        }

        let selectedHasFindings = selectedBatchItemID.flatMap { selectedID in
            batchItems.first { $0.id == selectedID }?.findingCount
        }.map { $0 > 0 } ?? false

        guard !selectedHasFindings,
              let firstFindingItem = batchItems.first(where: { $0.findingCount > 0 })
        else {
            return
        }

        selectBatchItem(firstFindingItem.id)
    }

    private func recordSafeShareHistory(
        sourceType: SafeShareSourceType? = nil,
        action: SafeShareAction,
        plan: RedactionPlan? = nil,
        outputPath: String? = nil,
        batchItemCount: Int? = nil
    ) {
        let resolvedSourceType = sourceType
            ?? selectedBatchItemID.flatMap { selectedID in
                batchItems.first { $0.id == selectedID }?.sourceType
            }
            ?? .unknown

        SafeShareHistorySettingsStorage.append(
            SafeShareHistoryRecord(
                sourceType: resolvedSourceType,
                action: action,
                plan: plan ?? redactionPlan,
                policySummary: safeSharePolicySummary,
                outputPath: outputPath,
                batchItemCount: batchItemCount
            )
        )
    }

    private var safeSharePolicySummary: String {
        let source = PolicySource(rawValue: policySourceID) ?? .local
        let sourceLabel: String
        switch source {
        case .local:
            sourceLabel = "Local policy"
        case .imported:
            sourceLabel = "Imported policy"
        case .managed:
            sourceLabel = "Managed policy"
        }

        guard
            let presetID = RedactionPolicyPresetID.normalized(rawValue: policyPresetID)
        else {
            return "\(sourceLabel): current defaults"
        }

        return "\(sourceLabel): \(RedactionPolicyCatalog.preset(presetID).title)"
    }

    @discardableResult
    private func loadImage(
        from url: URL,
        status: String = "Image loaded. Scanning on device...",
        autoDetect: Bool = true
    ) -> Bool {
        do {
            let importedImage = try ImageImporter.importImage(from: url)
            finishImageLoad(
                importedImage: importedImage,
                sourceURL: url,
                sourceType: .fileImport,
                status: status,
                autoDetect: autoDetect
            )
            return true
        } catch {
            failImageLoad(error)
            return false
        }
    }

    @discardableResult
    private func loadImage(
        from data: Data,
        sourceURL: URL? = nil,
        sourceLabel: String? = nil,
        sourceType: SafeShareSourceType = .unknown,
        status: String = "Image loaded. Scanning on device...",
        autoDetect: Bool = true
    ) -> Bool {
        do {
            let importedImage = try ImageImporter.importImage(from: data)
            finishImageLoad(
                importedImage: importedImage,
                sourceURL: sourceURL,
                sourceLabel: sourceLabel,
                sourceType: sourceType,
                status: status,
                autoDetect: autoDetect
            )
            return true
        } catch {
            failImageLoad(error)
            return false
        }
    }

    private func finishImageLoad(
        importedImage: ImportedImage,
        sourceURL: URL?,
        sourceLabel: String? = nil,
        sourceType: SafeShareSourceType = .unknown,
        status: String = "Image loaded. Scanning on device...",
        autoDetect: Bool = true
    ) {
        let item = BatchReviewItem(
            sourceURL: sourceURL,
            sourceLabel: sourceLabel,
            sourceType: sourceType,
            importedImage: importedImage,
            reviewStatusNote: status
        )
        replaceBatchItems([item], status: status, autoDetect: autoDetect)
    }

    private static func previewImage(from cgImage: CGImage) -> NSImage {
        NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private func failImageLoad(_ error: Error) {
        invalidateBatchScan()
        customSettingsRescanTask?.cancel()
        customSettingsRescanTask = nil
        image = nil
        cgImage = nil
        imageOrientation = .up
        redactionPlan = .empty
        selectedDetectionID = nil
        isManualEditing = false
        isPreviewingRedactedOutput = false
        redactedPreviewImage = nil
        completionBannerText = nil
        completionBannerAction = nil
        completionBannerTask?.cancel()
        completionBannerTask = nil
        manualEditHistory.reset()
        sourceImageURL = nil
        sourceDisplayLabel = nil
        batchItems = []
        selectedBatchItemID = nil
        batchFilter = .all

        if error as? RedaktrCoreError == .unsupportedImageType {
            errorText = "Use a PNG, JPEG, TIFF, or HEIC image."
        } else {
            errorText = "That image could not be opened."
        }
        reviewStatusNote = "Try another image."
    }

    private func clearCurrentReview() {
        guard canCloseCurrentReview else { return }

        invalidateBatchScan()
        customSettingsRescanTask?.cancel()
        customSettingsRescanTask = nil
        captureTask?.cancel()
        captureTask = nil
        activeCaptureMode = nil
        completionBannerText = nil
        completionBannerAction = nil
        completionBannerSecondaryAction = nil
        completionBannerTask?.cancel()
        completionBannerTask = nil
        shouldNotifyCustomSettingsRescanCompletion = false

        image = nil
        cgImage = nil
        imageOrientation = .up
        redactionPlan = .empty
        selectedDetectionID = nil
        isManualEditing = false
        keepsManualEditingAfterCommit = false
        isPreviewingRedactedOutput = false
        redactedPreviewImage = nil
        findingFilter = .all
        pendingShareAction = nil
        isShowingReviewWarning = false
        lastAutoCleanReviewItem = nil
        autoCleanUndoCoordinator.clear()
        manualEditHistory.reset()
        sourceImageURL = nil
        sourceDisplayLabel = nil
        batchItems = []
        selectedBatchItemID = nil
        batchFilter = .all
        includesCleanBatchExports = true
        errorText = nil
        reviewStatusNote = "Open, paste, or drop a PNG, JPEG, TIFF, or HEIC image. Redaktr works on device; review before sharing."
    }

    private func revealLastExportInFinder() {
        guard let lastExportLocation else { return }

        guard FileManager.default.fileExists(atPath: lastExportLocation.url.path) else {
            self.lastExportLocation = nil
            errorText = "The last exported \(lastExportLocation.isDirectory ? "folder" : "file") is no longer available."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([lastExportLocation.url])
    }

    private func reviewLastAutoCleanOutput() {
        guard let item = lastAutoCleanReviewItem else { return }

        replaceBatchItems([item], status: item.reviewStatusNote, autoDetect: false)
        selectedDetectionID = item.selectedDetectionID ?? item.redactionPlan.entries.first?.id
        revealMainWindowAfterCapture()
    }

    private func undoLastAutoCleanOutput() {
        guard autoCleanUndoCoordinator.undoLatest(clipboardProtectionController: clipboardProtectionController) else {
            showCompletion("No recent output could be undone")
            return
        }
        showCompletion("AutoClean undone")
    }

    private func scheduleCustomSettingsRescan() {
        guard cgImage != nil else { return }
        #if DEBUG
        if isUITestMode && ProcessInfo.processInfo.environment["REDAKTR_UI_SUPPRESS_AUTO_RESCAN"] == "1" {
            return
        }
        #endif

        customSettingsRescanTask?.cancel()
        invalidateBatchScan()
        for index in batchItems.indices {
            batchItems[index].scanState = .queued
            batchItems[index].didReviewInBatch = false
        }
        shouldNotifyCustomSettingsRescanCompletion = true
        errorText = nil
        reviewStatusNote = "Custom settings changed. Re-scanning current image..."

        customSettingsRescanTask = Task {
            do {
                try await Task.sleep(nanoseconds: 650_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard cgImage != nil else { return }
                customSettingsRescanTask = nil
                if isBatchReview {
                    startBatchDetection(for: batchItems.map(\.id))
                } else {
                    detectSensitiveText()
                }
            }
        }
    }

    private func refreshDetectionSettings(from notification: Notification) {
        guard let userInfo = notification.userInfo, !userInfo.isEmpty else {
            refreshDetectionSettingsFromDefaults()
            return
        }

        customTermsText = userInfo[RedaktrSettingsStorage.customTermsKey] as? String ?? ""
        customRegexesText = userInfo[RedaktrSettingsStorage.customRegexesKey] as? String ?? ""
        allowlistText = userInfo[RedaktrSettingsStorage.allowlistKey] as? String ?? ""
        policyPresetID = userInfo[RedaktrSettingsStorage.policyPresetKey] as? String ?? ""
        detectorCategoryPreferencesData = userInfo[RedaktrSettingsStorage.detectorCategoryPreferencesKey] as? Data ?? Data()
    }

    private func refreshDetectionSettingsFromDefaults() {
        let defaults = UserDefaults.standard
        customTermsText = defaults.string(forKey: RedaktrSettingsStorage.customTermsKey) ?? ""
        customRegexesText = defaults.string(forKey: RedaktrSettingsStorage.customRegexesKey) ?? ""
        allowlistText = defaults.string(forKey: RedaktrSettingsStorage.allowlistKey) ?? ""
        policyPresetID = defaults.string(forKey: RedaktrSettingsStorage.policyPresetKey) ?? ""
        detectorCategoryPreferencesData = defaults.data(forKey: RedaktrSettingsStorage.detectorCategoryPreferencesKey) ?? Data()
    }

    private func notifyCustomSettingsRescanCompletionIfNeeded() {
        guard shouldNotifyCustomSettingsRescanCompletion else { return }

        shouldNotifyCustomSettingsRescanCompletion = false
        NotificationCenter.default.post(name: .redaktrCustomDetectionSettingsRescanCompleted, object: nil)
    }

    private func startBatchDetection(for itemIDs: [BatchReviewItem.ID]) {
        guard !itemIDs.isEmpty else { return }
        syncCurrentStateToBatchItem()
        invalidateBatchScan()

        let targetIDs = Set(itemIDs)
        let configuration = customDetectionConfiguration
        let scanInputs = batchItems.compactMap { item -> BatchScanInput? in
            guard targetIDs.contains(item.id) else { return nil }
            return BatchScanInput(
                sourceFilename: item.sourceURL?.lastPathComponent,
                id: item.id,
                cgImage: item.importedImage.cgImage,
                orientation: item.importedImage.orientation,
                manualDetections: item.redactionPlan.manualDetections,
                manualActiveStates: Self.manualActiveStates(in: item.redactionPlan)
            )
        }
        guard !scanInputs.isEmpty else { return }

        for index in batchItems.indices where targetIDs.contains(batchItems[index].id) {
            batchItems[index].scanState = .queued
            batchItems[index].didReviewInBatch = false
        }
        let runID = UUID()
        batchRunID = runID

        batchScanTask = Task {
            for input in scanInputs {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard batchRunID == runID else { return }
                    markBatchItem(input.id, isChecking: true)
                }

                do {
                    #if DEBUG
                    if isUITestMode, let name = input.sourceFilename,
                       ProcessInfo.processInfo.environment["REDAKTR_UI_FAIL_SCAN_FILENAME"] == name {
                        throw RedaktrCoreError.textRecognitionFailed
                    }
                    #endif
                    let detector = SensitiveTextDetector(customConfiguration: configuration)
                    let plan = try await redactionPlan(
                        for: input.cgImage,
                        orientation: input.orientation,
                        detector: detector,
                        manualDetections: input.manualDetections,
                        manualActiveStates: input.manualActiveStates
                    )
                    try Task.checkCancellation()

                    await MainActor.run {
                        guard batchRunID == runID else { return }
                        applyBatchScanResult(plan, to: input.id)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        guard batchRunID == runID else { return }
                        markBatchItem(input.id, isChecking: false)
                    }
                    return
                } catch {
                    await MainActor.run {
                        guard batchRunID == runID else { return }
                        applyBatchScanFailure(to: input.id)
                    }
                }
            }

            await MainActor.run {
                guard batchRunID == runID else { return }
                focusBatchReviewAfterScanIfNeeded()
                batchScanTask = nil
                notifyCustomSettingsRescanCompletionIfNeeded()
            }
        }
    }

    private func markBatchItem(_ id: BatchReviewItem.ID, isChecking: Bool) {
        guard let index = batchItems.firstIndex(where: { $0.id == id }) else { return }
        batchItems[index].scanState = isChecking ? .scanning : .cancelled
        batchItems[index].errorText = nil
        batchItems[index].reviewStatusNote = isChecking
            ? "Checking text and visual content on device..."
            : Self.reviewStatusNote(for: batchItems[index].redactionPlan)

        if selectedBatchItemID == id {
            errorText = nil
            reviewStatusNote = batchItems[index].reviewStatusNote
            isManualEditing = false
            isPreviewingRedactedOutput = false
            redactedPreviewImage = nil
        }
    }

    private func applyBatchScanResult(_ plan: RedactionPlan, to id: BatchReviewItem.ID) {
        guard let index = batchItems.firstIndex(where: { $0.id == id }) else { return }

        batchItems[index].redactionPlan = plan
        batchItems[index].selectedDetectionID = batchItems[index].selectedDetectionID.flatMap { selectedID in
            plan.entries.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        batchItems[index].scanState = .succeeded
        if selectedBatchItemID == id, !plan.entries.isEmpty {
            batchItems[index].didReviewInBatch = true
        }
        batchItems[index].errorText = nil
        batchItems[index].reviewStatusNote = Self.reviewStatusNote(for: plan)
        recordSafeShareHistory(
            sourceType: batchItems[index].sourceType,
            action: .scan,
            plan: plan
        )

        if selectedBatchItemID == id {
            redactionPlan = plan
            selectedDetectionID = batchItems[index].selectedDetectionID
            errorText = nil
            isManualEditing = false
            isPreviewingRedactedOutput = false
            redactedPreviewImage = nil
            handlePlanChanged()
        }
    }

    private func applyBatchScanFailure(to id: BatchReviewItem.ID) {
        guard let index = batchItems.firstIndex(where: { $0.id == id }) else { return }

        let manualDetections = batchItems[index].redactionPlan.manualDetections
        var failurePlan = RedactionPlan(manualDetections: manualDetections)
        for (detectionID, isActive) in Self.manualActiveStates(in: batchItems[index].redactionPlan) {
            failurePlan.setActive(isActive, for: detectionID)
        }

        batchItems[index].redactionPlan = failurePlan
        batchItems[index].selectedDetectionID = batchItems[index].selectedDetectionID.flatMap { selectedID in
            failurePlan.entries.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        batchItems[index].scanState = .failed
        batchItems[index].errorText = "Detection failed. Automated detections were cleared."
        batchItems[index].reviewStatusNote = failurePlan.detections.isEmpty
            ? "Try Re-scan or draw a manual redaction."
            : "Review manual redactions or try Re-scan."

        if selectedBatchItemID == id {
            redactionPlan = failurePlan
            selectedDetectionID = batchItems[index].selectedDetectionID
            errorText = batchItems[index].errorText
            reviewStatusNote = batchItems[index].reviewStatusNote
            refreshRedactedPreviewIfNeeded()
        }
    }

    private func redactionPlan(
        for cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        detector: SensitiveTextDetector,
        manualDetections: [Detection],
        manualActiveStates: [Detection.ID: Bool]
    ) async throws -> RedactionPlan {
        #if DEBUG
        if let uiTestTextObservations {
            let found = detector.detections(in: uiTestTextObservations)
            return RedactionPlan(
                textDetections: found, manualDetections: manualDetections, manualActiveStates: manualActiveStates
            )
        }
        #endif

        async let textObservations = recognizer.recognizeText(in: cgImage, orientation: orientation)
        async let visualDetections = visualDetector.detections(
            in: cgImage,
            orientation: orientation,
            preferences: customDetectionConfiguration.detectorCategoryPreferences
        )
        let found = detector.detections(in: try await textObservations)
        let visualFound = try await visualDetections
        try Task.checkCancellation()

        return RedactionPlan(
            textDetections: found, visionDetections: visualFound,
            manualDetections: manualDetections, manualActiveStates: manualActiveStates
        )
    }

    #if DEBUG
    private var uiTestTextObservations: [TextObservation]? {
        guard isUITestMode,
              let text = ProcessInfo.processInfo.environment["REDAKTR_UI_TEST_TEXT_OBSERVATION"],
              !text.isEmpty
        else {
            return nil
        }

        return [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.12, y: 0.42, width: 0.76, height: 0.16),
                confidence: 0.99
            )
        ]
    }

    private var uiTestExportURL: URL? {
        guard isUITestMode else {
            return nil
        }

        if ProcessInfo.processInfo.environment["REDAKTR_UI_EXPORT_TO_APP_TEMP"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("redaktr-ui-export-\(UUID().uuidString)")
                .appendingPathExtension("png")
        }

        guard let path = ProcessInfo.processInfo.environment["REDAKTR_UI_EXPORT_PATH"],
              !path.isEmpty
        else { return nil }

        return URL(fileURLWithPath: path)
    }

    private var uiTestBatchExportRootURL: URL? {
        guard isUITestMode else {
            return nil
        }

        if ProcessInfo.processInfo.environment["REDAKTR_UI_BATCH_EXPORT_TO_APP_TEMP"] == "1" {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("redaktr-ui-batch-export-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }

        guard let path = ProcessInfo.processInfo.environment["REDAKTR_UI_BATCH_EXPORT_ROOT_PATH"],
              !path.isEmpty
        else { return nil }

        return URL(fileURLWithPath: path, isDirectory: true)
    }
    #endif

    private func detectSensitiveText() {
        guard let selectedBatchItemID else { return }
        customSettingsRescanTask?.cancel()
        customSettingsRescanTask = nil
        startBatchDetection(for: [selectedBatchItemID])
    }

    private func confirmManualReview() {
        guard let index = batchItems.firstIndex(where: { $0.id == selectedBatchItemID }),
              [.failed, .cancelled].contains(batchItems[index].scanState) else { return }
        batchItems[index].scanState = .manuallyReviewed
        batchItems[index].didReviewInBatch = true
        errorText = nil
        reviewStatusNote = "Manually reviewed. Copy or export will apply the current masks."
        syncCurrentStateToBatchItem()
    }

    private func exportRedacted() {
        guard requestReviewConfirmationIfNeeded(for: .export) else { return }
        performExportRedacted()
    }

    private func exportBatchRedacted() {
        syncCurrentStateToBatchItem()
        guard requestReviewConfirmationIfNeeded(for: .batchExport) else { return }
        performBatchExportRedacted()
    }

    private func performBatchExportRedacted() {
        guard let snapshot = outputSnapshot(for: .batchExport) else { return }
        let items = batchExportItems
        errorText = nil

        #if DEBUG
        if let destinationRoot = uiTestBatchExportRootURL {
            writeBatchExportRedacted(items: items, destinationRoot: destinationRoot)
            syncCurrentStateToBatchItem()
            return
        }
        #endif

        let panel = NSOpenPanel()
        panel.title = "Choose Batch Export Folder"
        panel.message = "Redaktr will create a Redaktr Cleaned folder here and write flattened cleaned PNG copies."
        panel.prompt = "Export Batch"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceImageURL?.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationRoot = panel.url else { return }

        guard snapshot == outputSnapshot(for: .batchExport) else {
            showChangedReviewMessage()
            return
        }
        writeBatchExportRedacted(items: items, destinationRoot: destinationRoot)
        syncCurrentStateToBatchItem()
    }

    private func performExportRedacted() {
        guard let snapshot = outputSnapshot(for: .export) else { return }
        errorText = nil

        #if DEBUG
        if let url = uiTestExportURL {
            writeRedactedExport(to: url)
            return
        }
        #endif

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = RedactedExportFilename.defaultName(for: sourceImageURL)
        panel.directoryURL = sourceImageURL?.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard snapshot == outputSnapshot(for: .export) else {
            showChangedReviewMessage()
            return
        }
        writeRedactedExport(to: url)
    }

    private func writeBatchExportRedacted(items: [BatchReviewItem], destinationRoot: URL) {
        do {
            let outputDirectory = try BatchOutputWriter.write(in: destinationRoot) { staging in
                var usedNames = Set<String>()
                for item in items {
                    let filename = RedactedExportFilename.batchOutputName(for: item.sourceURL, usedNames: &usedNames)
                    let data = try renderer.renderPNG(redacting: item.redactionPlan.activeDetections, in: item.importedImage.cgImage)
                    try data.write(to: staging.appendingPathComponent(filename), options: [.atomic])
                }
            }

            lastExportLocation = ExportLocation(url: outputDirectory, isDirectory: true)
            reviewStatusNote = "Exported \(items.count) cleaned PNG copies to \(outputDirectory.lastPathComponent). Source images were not changed."
            showCompletion("Exported \(items.count) cleaned copies", action: .revealLastExport)
            recordBatchExportHistory(items: items, outputPath: outputDirectory.path)
        } catch {
            errorText = "Batch export failed. Choose another folder and try again."
            reviewStatusNote = "No batch export was completed."
        }
    }

    private func writeRedactedExport(to url: URL) {
        guard canShareSelected else { return }
        guard !batchItems.contains(where: { $0.sourceIdentity?.matches(url) == true }) else {
            errorText = "Choose a different filename to keep the source image."
            return
        }
        do {
            let output = try redactedImageData(for: url)
            try output.data.write(to: url, options: [.atomic])
            lastExportLocation = ExportLocation(url: url, isDirectory: false)
            reviewStatusNote = "Cleaned \(output.formatName) exported. Share that file; the source image was not changed."
            showCompletion("Exported cleaned \(output.formatName)", action: .revealLastExport)
            recordSafeShareHistory(action: .exportCleanedImage, outputPath: url.path)
        } catch {
            errorText = "Export failed. Choose another save location."
            reviewStatusNote = "No file was written."
        }
    }

    private func copyRedacted() {
        guard requestReviewConfirmationIfNeeded(for: .copy) else { return }
        performCopyRedacted()
    }

    private func performCopyRedacted() {
        guard canShareSelected else { return }
        errorText = nil

        do {
            let data = try redactedPNGData()
            let pasteboard = RedaktrPasteboard.current
            let previous = ClipboardUndoSnapshot.capture(from: pasteboard)
            guard let generation = try previous.replace(with: data, in: pasteboard) else {
                errorText = "The clipboard changed. Copy again when ready."
                return
            }
            clipboardProtectionController.markHandled(changeCount: generation)
            reviewStatusNote = "Cleaned PNG copied. Paste this shareable artifact; the source image was not changed."
            showCompletion("Copied cleaned PNG")
            recordSafeShareHistory(action: .copyCleanedPNG)
        } catch {
            errorText = "Copy failed. Try exporting the redacted PNG instead."
            reviewStatusNote = "No image was copied."
        }
    }

    private func outputSnapshot(for action: ShareAction) -> [ReviewedOutput]? {
        if action == .batchExport {
            return canShareBatch ? batchExportItems.map(ReviewedOutput.init) : nil
        }
        guard let selectedItem, selectedItem.scanState.allowsOutput else { return nil }
        return [ReviewedOutput(selectedItem)]
    }

    private func showChangedReviewMessage() {
        errorText = "The review changed. Check the current image and start the export or copy again."
    }

    private func requestReviewConfirmationIfNeeded(for action: ShareAction) -> Bool {
        guard let snapshot = outputSnapshot(for: action) else {
            if cgImage != nil { errorText = "Complete the scan or explicitly review failed images before exporting or copying." }
            return false
        }
        let count = action == .batchExport ? batchReviewNeededCount : reviewNeededCount
        guard count > 0 else { return true }

        pendingShareItems = snapshot
        pendingShareAction = action
        isShowingReviewWarning = true
        return false
    }

    private func performPendingShareAction() {
        let action = pendingShareAction
        let approved = pendingShareItems
        cancelPendingShareAction()
        guard let action, approved == outputSnapshot(for: action) else {
            showChangedReviewMessage()
            return
        }
        switch action {
        case .copy:
            performCopyRedacted()
        case .export:
            performExportRedacted()
        case .batchExport:
            performBatchExportRedacted()
        }
    }

    private func cancelPendingShareAction() {
        pendingShareAction = nil
        pendingShareItems = []
    }

    private func presentAutoCleanReceipt(_ receipt: AutoCleanReceipt) {
        if !isUITestMode,
           RedaktrAutoCleanReceiptRouter.route(isAppActive: NSApp.isActive) == .systemNotification {
            ScreenshotWatchRiskNotifier.notifyAutoCleanReceipt(
                title: receipt.title,
                body: receipt.notificationBody
            )
        } else {
            showCompletion(
                receipt.title,
                action: receipt.primaryAction,
                secondaryAction: receipt.secondaryAction
            )
        }
    }

    private func showCompletion(
        _ text: String,
        action: CompletionBannerAction? = nil,
        secondaryAction: CompletionBannerAction? = nil
    ) {
        completionBannerTask?.cancel()
        completionBannerText = text
        completionBannerAction = action
        completionBannerSecondaryAction = secondaryAction

        completionBannerTask = Task {
            try? await Task.sleep(nanoseconds: secondaryAction == nil ? 2_400_000_000 : 8_000_000_000)
            await MainActor.run {
                if completionBannerText == text {
                    completionBannerText = nil
                    completionBannerAction = nil
                    completionBannerSecondaryAction = nil
                }
            }
        }
    }

    private func performCompletionBannerAction(_ action: CompletionBannerAction?) {
        guard let action else { return }

        switch action {
        case .revealLastExport:
            revealLastExportInFinder()
        case .reviewLatestWatchedScreenshot:
            openLatestWatchedScreenshot()
        case .reviewLastAutoClean:
            reviewLastAutoCleanOutput()
        case .undoLastAutoClean:
            undoLastAutoCleanOutput()
        case .openNotificationSettings:
            ScreenshotWatchRiskNotifier.openNotificationSettings()
        }
    }

    private func recordBatchExportHistory(items: [BatchReviewItem], outputPath: String) {
        let totalFindings = items.reduce(0) { $0 + $1.redactionPlan.entries.count }
        let includedFindings = items.reduce(0) { $0 + $1.redactionPlan.activeDetections.count }
        let reviewFindings = items.reduce(0) { partial, item in
            partial + item.redactionPlan.entries.filter { $0.isActive && $0.needsReview }.count
        }
        let sourceType: SafeShareSourceType = items.count > 1
            ? .folderBatch
            : (items.first?.sourceType ?? .unknown)

        SafeShareHistorySettingsStorage.append(
            SafeShareHistoryRecord(
                sourceType: sourceType,
                action: .batchExport,
                totalFindings: totalFindings,
                includedFindings: includedFindings,
                reviewFindings: reviewFindings,
                offFindings: totalFindings - includedFindings,
                policySummary: safeSharePolicySummary,
                outputPath: outputPath,
                batchItemCount: items.count
            )
        )
    }

    private func redactedPNGData() throws -> Data {
        guard let cgImage else {
            throw RedaktrCoreError.invalidImageData
        }

        return try renderer.renderPNG(redacting: redactionPlan.activeDetections, in: cgImage)
    }

    private func redactedImageData(for url: URL) throws -> (data: Data, formatName: String) {
        guard let cgImage else {
            throw RedaktrCoreError.invalidImageData
        }

        if Self.isJPEGExportURL(url) {
            return (try renderer.renderJPEG(redacting: redactionPlan.activeDetections, in: cgImage), "JPEG")
        }

        return (try renderer.renderPNG(redacting: redactionPlan.activeDetections, in: cgImage), "PNG")
    }

    private static func isJPEGExportURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "jpg" || pathExtension == "jpeg"
    }

    private func clipboardImageData() -> Data? {
        ClipboardImageReader.imageData(in: RedaktrPasteboard.current)
    }

    private func handleAppear() {
        globalCaptureShortcutController.start { mode in
            NotificationCenter.default.post(name: .redaktrCaptureRequested, object: mode)
        }
        loadLaunchFixtureIfNeeded()
        refreshScreenshotWatch()
        refreshClipboardProtection()
        if !applicationInstallController.evaluateOnLaunch(isUITestMode: isUITestMode) {
            showFirstLaunchOnboardingIfNeeded()
        }
    }

    private func handleDisappear() {
        globalCaptureShortcutController.stop()
        invalidateBatchScan()
        customSettingsRescanTask?.cancel()
        customSettingsRescanTask = nil
        completionBannerTask?.cancel()
        completionBannerAction = nil
        completionBannerTask = nil
        for task in watchedScreenshotScanTasks.values {
            task.cancel()
        }
        watchedScreenshotScanTasks = [:]
        screenshotWatchController.stop()
        for task in clipboardProtectionScanTasks.values {
            task.cancel()
        }
        clipboardProtectionScanTasks = [:]
        clipboardProtectionController.stop()
        captureTask?.cancel()
        captureTask = nil
        activeCaptureMode = nil
    }

    private func showFirstLaunchOnboardingIfNeeded() {
        let shouldShowInUITestMode = ProcessInfo.processInfo.environment["REDAKTR_UI_FORCE_ONBOARDING"] == "1"
        guard (!isUITestMode || shouldShowInUITestMode), !didCompleteOnboarding, activeHelpSheet == nil else { return }
        DispatchQueue.main.async {
            presentHelpSheet(.onboarding)
        }
    }

    private func presentHelpSheet(_ sheet: RedaktrHelpSheet) {
        lastPresentedHelpSheet = sheet
        activeHelpSheet = sheet
    }

    private func helpSheetContent(for sheet: RedaktrHelpSheet) -> AnyView {
        switch sheet {
        case .onboarding:
            return AnyView(
                RedaktrOnboardingView(
                    onFinish: finishOnboarding,
                    onTrySample: trySampleFromOnboarding,
                    onOpenHelp: openHelpFromOnboarding
                )
            )
        case .helpCenter:
            return AnyView(
                RedaktrHelpCenterView(
                    onShowQuickStart: showOnboardingFromHelp,
                    onOpenSettings: openSettingsFromHelp,
                    onClose: dismissHelpSheet
                )
            )
        }
    }

    private func handleHelpSheetDismiss() {
        if lastPresentedHelpSheet == .onboarding {
            markOnboardingComplete()
        }
        lastPresentedHelpSheet = nil
    }

    private func markOnboardingComplete() {
        didCompleteOnboarding = true
    }

    private func finishOnboarding() {
        markOnboardingComplete()
        activeHelpSheet = nil
    }

    private func trySampleFromOnboarding() {
        markOnboardingComplete()
        activeHelpSheet = nil
        #if DEBUG
        uiTestSampleStatus = "requested"
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            loadSampleImage()
        }
    }

    private func loadSampleImage() {
        do {
            #if DEBUG
            if isUITestMode {
                let importedImage = try Self.uiTestSampleImportedImage()
                let detection = Self.fixtureDetectionForUITest(index: 0)
                let plan = RedactionPlan(textDetections: [detection])
                let status = "Sample image loaded. Review every box, then export a cleaned copy."
                uiTestSampleStatus = "loaded \(plan.entries.count)"
                let item = BatchReviewItem(
                    sourceURL: nil,
                    sourceLabel: "Redaktr sample",
                    sourceType: .unknown,
                    importedImage: importedImage,
                    redactionPlan: plan,
                    selectedDetectionID: detection.id,
                    reviewStatusNote: status,
                    scanState: .succeeded
                )
                replaceBatchItems([item], status: status, autoDetect: false)
                return
            }
            #endif

            let importedImage = ImportedImage(cgImage: try RedaktrSampleImage.cgImage(), orientation: .up)
            let detection = Self.sampleDetection()
            let status = "Sample image loaded. Review every box, then export a cleaned copy."
            let item = BatchReviewItem(
                sourceURL: nil,
                sourceLabel: "Redaktr sample",
                sourceType: .unknown,
                importedImage: importedImage,
                redactionPlan: RedactionPlan(textDetections: [detection]),
                selectedDetectionID: detection.id,
                reviewStatusNote: status,
                scanState: .succeeded
            )
            replaceBatchItems([item], status: status, autoDetect: false)
        } catch {
            errorText = "Sample image could not be created."
            reviewStatusNote = "Open or paste an image to start."
            #if DEBUG
            uiTestSampleStatus = "failed"
            #endif
        }
    }

    #if DEBUG
    private static func uiTestSampleImportedImage() throws -> ImportedImage {
        let width = 1120
        let height = 720
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RedaktrCoreError.imageRenderFailed
        }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fill(CGRect(x: 56, y: 64, width: 1008, height: 592))

        guard let cgImage = context.makeImage() else {
            throw RedaktrCoreError.imageRenderFailed
        }

        return ImportedImage(cgImage: cgImage, orientation: .up)
    }
    #endif

    private static func sampleDetection() -> Detection {
        Detection(
            id: UUID(uuidString: "33333333-4444-5555-6666-777777777777")!,
            kind: .secret,
            label: "Sample secret",
            confidence: 0.96,
            normalizedBounds: CGRect(x: 0.08, y: 0.515, width: 0.74, height: 0.06),
            source: .deterministic,
            reason: "Sample finding for the Quick Start.",
            matchedText: "AKIAIOSFODNN7EXAMPLE",
            matchedRange: TextRange(location: 0, length: 20),
            suggestedAction: .redact,
            boundsPrecision: .tight
        )
    }

    private func dismissHelpSheet() {
        activeHelpSheet = nil
    }

    private func openHelpFromOnboarding() {
        markOnboardingComplete()
        presentHelpSheetAfterDismissingCurrent(.helpCenter)
    }

    private func openSettingsFromHelp() {
        dismissHelpSheet()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            openSettings()
        }
    }

    private func showOnboardingFromHelp() {
        presentHelpSheetAfterDismissingCurrent(.onboarding)
    }

    private func presentHelpSheetAfterDismissingCurrent(_ sheet: RedaktrHelpSheet) {
        activeHelpSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            presentHelpSheet(sheet)
        }
    }

    private var isUITestMode: Bool {
        RedaktrUITestEnvironment.isEnabled
    }

    private func seedUITestDetectionsIfNeeded() {
        guard isUITestMode else { return }
        guard ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_DETECTIONS"] == "1" else { return }

        guard !batchItems.isEmpty else { return }

        let seedsFirstItemOnly = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_DETECTIONS_FIRST_ITEM_ONLY"] == "1"
        let seedsManualDetection = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_MANUAL_DETECTION"] == "1"
        let seedsReviewDetection = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_REVIEW_DETECTION"] == "1"
        let seedsMixedBatchCategories = ProcessInfo.processInfo.environment["REDAKTR_UI_SEED_MIXED_BATCH_CATEGORIES"] == "1"

        for index in batchItems.indices {
            if seedsFirstItemOnly && index > 0 {
                batchItems[index].redactionPlan = .empty
                batchItems[index].selectedDetectionID = nil
                batchItems[index].scanState = .succeeded
                batchItems[index].errorText = nil
                batchItems[index].reviewStatusNote = "Fixture clean image loaded."
                continue
            }

            let fixtureDetection = seedsMixedBatchCategories && index > 0
                ? Self.fixtureCustomerAccountDetectionForUITest(index: index)
                : Self.fixtureDetectionForUITest(index: index)
            var textDetections = [fixtureDetection]
            if seedsReviewDetection {
                textDetections.append(Self.fixtureReviewDetectionForUITest())
            }

            let manualDetection = seedsManualDetection
                ? Self.fixtureManualDetectionForUITest()
                : nil
            batchItems[index].redactionPlan = RedactionPlan(
                textDetections: textDetections,
                manualDetections: manualDetection.map { [$0] } ?? []
            )
            batchItems[index].selectedDetectionID = manualDetection?.id ?? fixtureDetection.id
            batchItems[index].scanState = .succeeded
            batchItems[index].errorText = nil
            batchItems[index].reviewStatusNote = "Fixture detection loaded. Review every box, then export a cleaned copy."
        }

        guard let selectedBatchItemID,
              let selectedItem = batchItems.first(where: { $0.id == selectedBatchItemID })
        else {
            return
        }

        redactionPlan = selectedItem.redactionPlan
        selectedDetectionID = selectedItem.selectedDetectionID
        isManualEditing = false
        isPreviewingRedactedOutput = false
        redactedPreviewImage = nil
        errorText = nil
        reviewStatusNote = selectedItem.reviewStatusNote
        syncCurrentStateToBatchItem()
        markBatchItemReviewed(selectedBatchItemID)
        focusBatchReviewAfterScanIfNeeded()
    }

    private func seedUITestWatchedScreenshotIfNeeded() {
        guard isUITestMode else { return }
        guard
            let watchedFixturePath = ProcessInfo.processInfo.environment["REDAKTR_UI_WATCHED_FIXTURE_PATH"],
            !watchedFixturePath.isEmpty
        else {
            return
        }

        let watchedURL = URL(fileURLWithPath: watchedFixturePath)
        do {
            let importedImage = try ImageImporter.importImage(from: watchedURL)
            let detection = Detection(
                id: UUID(uuidString: "77777777-8888-9999-AAAA-BBBBBBBBBBBB")!,
                kind: .email,
                label: "Watched fixture email",
                confidence: 0.95,
                normalizedBounds: CGRect(x: 0.16, y: 0.54, width: 0.46, height: 0.16),
                source: .deterministic,
                reason: "Synthetic watched screenshot detection.",
                matchedText: "watch@example.com",
                matchedRange: TextRange(location: 0, length: 17),
                suggestedAction: .redact,
                boundsPrecision: .tight
            )
            handleWatchedScreenshotScanResult(
                RedactionPlan(textDetections: [detection]),
                importedImage: importedImage,
                sourceURL: watchedURL
            )
        } catch {
            reviewStatusNote = "Watched fixture could not be loaded."
        }
    }

    private static func fixtureDetectionForUITest(index: Int) -> Detection {
        let id = index == 0
            ? UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            : UUID()

        return Detection(
            id: id,
            kind: .email,
            label: "UI fixture email",
            confidence: 0.95,
            normalizedBounds: CGRect(x: 0.14, y: 0.58, width: 0.48, height: 0.16),
            source: .deterministic,
            reason: "Synthetic UI fixture detection.",
            matchedText: "user@example.com",
            matchedRange: TextRange(location: 0, length: 16),
            suggestedAction: .redact,
            boundsPrecision: .tight
        )
    }

    private static func fixtureReviewDetectionForUITest() -> Detection {
        Detection(
            id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            kind: .unknown,
            label: "UI fixture review item",
            confidence: 0.72,
            normalizedBounds: CGRect(x: 0.18, y: 0.32, width: 0.38, height: 0.12),
            source: .deterministic,
            reason: "Synthetic UI fixture review detection.",
            matchedText: "account_1234567",
            matchedRange: TextRange(location: 0, length: 15),
            suggestedAction: .review,
            boundsPrecision: .tight
        )
    }

    private static func fixtureCustomerAccountDetectionForUITest(index: Int) -> Detection {
        let matchedText = "customer_01HZYXWVUTSRQPONMLKJIHGF\(index)"
        return Detection(
            id: UUID(),
            kind: .unknown,
            label: "Account/customer ID",
            confidence: 0.72,
            normalizedBounds: CGRect(x: 0.16, y: 0.52, width: 0.42, height: 0.14),
            source: .deterministic,
            reason: "Synthetic UI fixture customer/account detection.",
            matchedText: matchedText,
            matchedRange: TextRange(location: 0, length: matchedText.count),
            suggestedAction: .review,
            boundsPrecision: .tight
        )
    }

    private static func fixtureManualDetectionForUITest() -> Detection {
        RedactionPlan.manualRedaction(
            bounds: CGRect(x: 0.18, y: 0.18, width: 0.34, height: 0.12),
            reason: "Synthetic UI fixture manual redaction."
        )
    }

    private func invalidateBatchScan() {
        batchRunID = UUID()
        batchScanTask?.cancel()
        batchScanTask = nil
        for index in batchItems.indices where [.queued, .scanning].contains(batchItems[index].scanState) {
            batchItems[index].scanState = .cancelled
            batchItems[index].reviewStatusNote = "Scan cancelled. Re-scan or review this image manually."
        }
    }

    private func cancelDetection() {
        invalidateBatchScan()
        errorText = nil
        reviewStatusNote = image == nil
            ? "Open, paste, or drop a PNG, JPEG, TIFF, or HEIC image. Redaktr works on device; review before sharing."
            : "Detection canceled. Review existing boxes or Re-scan."
    }

    private func setManualEditing(_ isEditing: Bool) {
        guard image != nil, !isChecking else {
            isManualEditing = false
            return
        }

        if isEditing {
            isPreviewingRedactedOutput = false
            redactedPreviewImage = nil
        }
        isManualEditing = isEditing
        errorText = nil
        if isEditing {
            reviewStatusNote = "Draw a manual redaction on the image."
        } else {
            updateReviewStatus()
        }
    }

    private func deleteSelectedManualRedaction() {
        guard let selectedManualRedactionID else { return }

        let previousPlan = redactionPlan
        if redactionPlan.removeManualRedaction(id: selectedManualRedactionID) {
            manualEditHistory.recordChange(from: previousPlan, to: redactionPlan)
            selectedDetectionID = nil
            handlePlanChanged()
        }
    }

    private func resetSelectedBounds() {
        guard let selectedAdjustedRedactionID else { return }

        let previousPlan = redactionPlan
        if redactionPlan.resetRedactionBounds(id: selectedAdjustedRedactionID) {
            manualEditHistory.recordChange(from: previousPlan, to: redactionPlan)
            handlePlanChanged()
            reviewStatusNote = "Selected box reset to its original detected bounds."
        }
    }

    private func recordManualEdit(from oldPlan: RedactionPlan, to newPlan: RedactionPlan) {
        manualEditHistory.recordChange(from: oldPlan, to: newPlan)
    }

    private func undoManualEdit() {
        guard !isChecking else { return }
        guard manualEditHistory.undo(in: &redactionPlan) else { return }

        isManualEditing = false
        clearMissingSelection()
        handlePlanChanged()
    }

    private func redoManualEdit() {
        guard !isChecking else { return }
        guard manualEditHistory.redo(in: &redactionPlan) else { return }

        isManualEditing = false
        clearMissingSelection()
        handlePlanChanged()
    }

    private func clearMissingSelection() {
        if let selectedDetectionID, !redactionPlan.entries.contains(where: { $0.id == selectedDetectionID }) {
            self.selectedDetectionID = nil
        }
    }

    private func updateReviewStatus() {
        if isManualEditing {
            reviewStatusNote = "Draw a manual redaction on the image."
        } else {
            reviewStatusNote = Self.reviewStatusNote(for: redactionPlan)
        }
    }

    private static func manualActiveStates(in plan: RedactionPlan) -> [Detection.ID: Bool] {
        Dictionary(
            uniqueKeysWithValues: plan.entries
                .filter { $0.detection.source == .user }
                .map { ($0.id, $0.isActive) }
        )
    }

    private static func reviewNeededCount(in plan: RedactionPlan) -> Int {
        plan.entries.filter { entry in
            guard entry.isActive else { return false }

            return entry.needsReview
        }.count
    }

    private static func reviewStatusNote(for plan: RedactionPlan) -> String {
        let activeCount = plan.activeDetections.count
        let reviewNeededCount = reviewNeededCount(in: plan)

        if plan.detections.isEmpty {
            return "No obvious sensitive content found. Review the image manually before sharing."
        } else if activeCount == 0 {
            return "All findings are off. Copy or export still creates a flattened cleaned image."
        } else if reviewNeededCount > 0 {
            return "\(reviewNeededCount) detections need closer review before export."
        } else {
            return "Review the boxes, then export a cleaned image or copy a PNG."
        }
    }

    private static func uniqueCaptureOutputURL(
        in folder: URL,
        mode: RedaktrCaptureMode,
        date: Date
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let stem = "Redaktr-\(mode.rawValue)-\(formatter.string(from: date))-cleaned"
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension("png")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder
                .appendingPathComponent("\(stem)-\(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }

        return candidate
    }
}

private struct ContentPresentationModifier: ViewModifier {
    @Binding var isShowingReviewWarning: Bool
    let shareContinueLabel: String
    let shareWarningMessage: String
    let continueShare: () -> Void
    let cancelShare: () -> Void
    @Binding var activeHelpSheet: RedaktrHelpSheet?
    let handleHelpSheetDismiss: () -> Void
    let helpSheetContent: (RedaktrHelpSheet) -> AnyView

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Review findings before sharing?",
                isPresented: $isShowingReviewWarning,
                titleVisibility: .visible
            ) {
                Button(shareContinueLabel, action: continueShare)
                Button("Cancel", role: .cancel, action: cancelShare)
            } message: {
                Text(shareWarningMessage)
            }
            .sheet(item: $activeHelpSheet, onDismiss: handleHelpSheetDismiss, content: helpSheetContent)
    }
}

private struct BatchQueueTable: NSViewRepresentable {
    let items: [BatchReviewItem]
    let selectedID: BatchReviewItem.ID?
    let onSelect: (BatchReviewItem.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, selectedID: selectedID, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 70
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.setAccessibilityIdentifier("batch-items-list")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("image"))
        tableView.addTableColumn(column)

        let scrollView = KeyHandlingScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.setAccessibilityIdentifier("batch-items-list")
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        context.coordinator.selectedID = selectedID
        context.coordinator.onSelect = onSelect
        (scrollView as? KeyHandlingScrollView)?.onMove = { offset in
            context.coordinator.moveSelection(offset: offset)
        }

        guard let tableView = context.coordinator.tableView else { return }
        if tableView.tableColumns.first?.width != scrollView.contentSize.width {
            tableView.tableColumns.first?.width = scrollView.contentSize.width
        }
        tableView.reloadData()
        context.coordinator.selectCurrentRow()

        DispatchQueue.main.async {
            guard let window = scrollView.window,
                  window.firstResponder !== tableView
            else {
                return
            }

            window.makeFirstResponder(tableView)
        }
    }

    final class KeyHandlingScrollView: NSScrollView {
        var onMove: (Int) -> Void = { _ in }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func keyDown(with event: NSEvent) {
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                super.keyDown(with: event)
                return
            }

            if event.specialKey == .upArrow || event.keyCode == 126 {
                onMove(-1)
                return
            }

            if event.specialKey == .downArrow || event.keyCode == 125 {
                onMove(1)
                return
            }

            super.keyDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var items: [BatchReviewItem]
        var selectedID: BatchReviewItem.ID?
        var onSelect: (BatchReviewItem.ID) -> Void
        weak var tableView: NSTableView?
        private var isSelectingProgrammatically = false

        init(
            items: [BatchReviewItem],
            selectedID: BatchReviewItem.ID?,
            onSelect: @escaping (BatchReviewItem.ID) -> Void
        ) {
            self.items = items
            self.selectedID = selectedID
            self.onSelect = onSelect
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            70
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard items.indices.contains(row) else { return nil }

            let item = items[row]
            let host = NSHostingView(
                rootView: BatchQueueRow(
                    item: item,
                    isSelected: selectedID == item.id
                )
            )
            host.translatesAutoresizingMaskIntoConstraints = false

            let cellIdentifier = "batch-row-\(item.displayName)"
            let cell = NSTableCellView()
            cell.identifier = NSUserInterfaceItemIdentifier(cellIdentifier)
            cell.setAccessibilityIdentifier(cellIdentifier)
            cell.addSubview(host)

            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                host.topAnchor.constraint(equalTo: cell.topAnchor),
                host.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
            ])

            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSelectingProgrammatically,
                  let tableView,
                  tableView.selectedRow >= 0,
                  items.indices.contains(tableView.selectedRow)
            else {
                return
            }

            onSelect(items[tableView.selectedRow].id)
        }

        func selectCurrentRow() {
            guard let tableView,
                  let selectedID,
                  let row = items.firstIndex(where: { $0.id == selectedID })
            else {
                return
            }

            guard tableView.selectedRow != row else { return }
            isSelectingProgrammatically = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            isSelectingProgrammatically = false
        }

        func moveSelection(offset: Int) {
            guard !items.isEmpty else { return }

            let currentRow: Int
            if let tableView, tableView.selectedRow >= 0 {
                currentRow = tableView.selectedRow
            } else if let selectedID,
                      let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) {
                currentRow = selectedIndex
            } else {
                currentRow = offset > 0 ? -1 : items.count
            }

            let nextRow = (currentRow + offset + items.count) % items.count
            selectedID = items[nextRow].id
            onSelect(items[nextRow].id)
            selectCurrentRow()
        }
    }
}

private struct BatchQueueRow: View {
    let item: BatchReviewItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if item.isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: item.statusIcon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(item.statusColor)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                Text(item.statusLabel)
                    .font(.caption)
                    .foregroundStyle(item.statusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if item.needsBatchReview {
                Text("New")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("batch-row-\(item.displayName)")
        .accessibilityLabel("\(item.displayName), \(item.statusLabel)\(item.needsBatchReview ? ", new finding image" : "")")
    }

    private var rowBorderColor: Color {
        if isSelected { return .accentColor }
        if item.needsBatchReview { return .orange.opacity(0.7) }
        return .secondary.opacity(0.18)
    }
}

private struct DetectionGroupSection: View {
    let group: FindingGroup
    let selectedDetectionID: Detection.ID?
    let activeBinding: (Detection.ID) -> Binding<Bool>
    let onSelect: (Detection.ID) -> Void
    let onSetGroupActive: (Bool, [Detection.ID]) -> Void
    let onRememberSafe: (RedactionPlanEntry) -> Void
    let onSetDetectorDisposition: (RedactionPolicyDisposition, RedactionPlanEntry) -> Void
    let onOpenDetectionSettings: () -> Void

    private var activeCount: Int {
        group.entries.filter(\.isActive).count
    }

    private var allActive: Bool {
        activeCount == group.entries.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("\(group.category.displayName) - \(group.entries.count)", systemImage: group.category.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(allActive ? "Make visible" : "Redact") {
                    onSetGroupActive(!allActive, group.entries.map(\.id))
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("toggle-\(group.category.rawValue)-findings-button")
            }

            VStack(spacing: 8) {
                ForEach(group.entries) { entry in
                    DetectionRow(
                        entry: entry,
                        isSelected: selectedDetectionID == entry.id,
                        onSelect: { onSelect(entry.id) },
                        isActive: activeBinding(entry.id),
                        onRememberSafe: { onRememberSafe(entry) },
                        onSetDetectorDisposition: { disposition in onSetDetectorDisposition(disposition, entry) },
                        onOpenDetectionSettings: onOpenDetectionSettings
                    )
                }
            }
        }
    }
}

private struct DetectionRow: View {
    let entry: RedactionPlanEntry
    let isSelected: Bool
    let onSelect: () -> Void
    @Binding var isActive: Bool
    let onRememberSafe: () -> Void
    let onSetDetectorDisposition: (RedactionPolicyDisposition) -> Void
    let onOpenDetectionSettings: () -> Void
    @State private var showsDetectorDetails = false

    private var detection: Detection {
        entry.detection
    }

    private var confidenceSummary: ConfidenceSummary {
        ConfidenceSummary(detection: detection, isActive: isActive)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $isActive)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("detection-toggle-\(entry.id.uuidString)")
                .accessibilityLabel("\(detection.label), \(detection.kind.displayName)")
                .accessibilityValue(isActive ? "Will redact in export" : "Visible in export")
                .accessibilityHint("Toggles whether this finding is redacted in the cleaned copy.")

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(detection.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    HStack(spacing: 6) {
                        if detection.hasAdjustedBounds {
                            AdjustedChip()
                        }
                        ConfidenceChip(summary: confidenceSummary)
                    }
                    .layoutPriority(1)
                }

                if isSelected {
                    Text(PolicyActionExplanation(entry: entry).displayText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("policy-action-reason-\(entry.id.uuidString)")

                    Text(detection.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup("Detector details", isExpanded: $showsDetectorDetails) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Group: \(detection.detectorCategory.displayName)")
                            Text("Taxonomy: \(detection.detectorCategory.taxonomyGroup.displayName)")
                            Text("Current action: \(RedactionPolicyDisposition(suggestedAction: detection.suggestedAction).displayName)")
                            Text("Bounds: \(detection.boundsPrecision.rawValue)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("detector-details-disclosure")

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(RedactionPolicyDisposition.allCases, id: \.rawValue) { disposition in
                                Button(disposition.displayName) {
                                    onSetDetectorDisposition(disposition)
                                }
                                .accessibilityIdentifier("detector-disposition-\(disposition.rawValue)-button")
                            }
                        } label: {
                            Label("Change detector setting", systemImage: "slider.horizontal.3")
                        }
                        .menuStyle(.borderlessButton)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("change-detector-setting-menu")

                        Button(action: onOpenDetectionSettings) {
                            Label("Open Detection settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("open-detection-settings-from-finding-button")
                    }

                }

                if isSelected && canRememberAsSafe {
                    Button(action: onRememberSafe) {
                        Label("Remember exact text as safe", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("remember-safe-finding-button")
                    .accessibilityHint("Adds only this exact matched string to the local allowlist and leaves it visible.")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detection-row-\(entry.id.uuidString)")
        .accessibilityHint("Selects this detection for review and centers it on the image.")
    }

    private var rowBackground: Color {
        isActive
            ? Color(nsColor: .textBackgroundColor)
            : Color(nsColor: .textBackgroundColor).opacity(0.55)
    }

    private var rowBorderColor: Color {
        if isSelected { return .accentColor }
        return isActive ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.25)
    }

    private var canRememberAsSafe: Bool {
        guard detection.source == .deterministic,
              let matchedText = detection.matchedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }

        return !matchedText.isEmpty
    }
}

private struct ConfidenceChip: View {
    let summary: ConfidenceSummary

    var body: some View {
        Label(summary.label, systemImage: summary.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(summary.foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(summary.backgroundColor, in: Capsule())
            .accessibilityLabel(summary.label)
    }
}

private struct AdjustedChip: View {
    var body: some View {
        Label("Adjusted", systemImage: "slider.horizontal.3")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .accessibilityLabel("Bounds adjusted")
    }
}

private struct ConfidenceSummary {
    let label: String
    let systemImage: String
    let foregroundColor: Color
    let backgroundColor: Color

    init(detection: Detection, isActive: Bool) {
        if !isActive {
            label = "Visible"
            systemImage = "pause.circle"
            foregroundColor = .secondary
            backgroundColor = Color(nsColor: .controlBackgroundColor)
        } else if detection.boundsPrecision == .lineFallback {
            label = "Check bounds"
            systemImage = "rectangle.dashed"
            foregroundColor = .orange
            backgroundColor = .orange.opacity(0.14)
        } else if detection.suggestedAction == .review || detection.confidence < 0.8 {
            label = "Check"
            systemImage = "exclamationmark.triangle"
            foregroundColor = .orange
            backgroundColor = .orange.opacity(0.14)
        } else if detection.confidence >= 0.9 {
            label = "High"
            systemImage = "checkmark.seal"
            foregroundColor = .green
            backgroundColor = Color.green.opacity(0.14)
        } else {
            label = "Medium"
            systemImage = "questionmark.circle"
            foregroundColor = .secondary
            backgroundColor = Color(nsColor: .controlBackgroundColor)
        }
    }
}

private enum RedactedExportFilename {
    static func defaultName(for sourceURL: URL?) -> String {
        guard let sourceURL else { return "redacted.png" }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStem = stem.isEmpty ? "redacted" : stem

        return "\(safeStem)-redacted.png"
    }

    static func batchOutputName(for sourceURL: URL?, usedNames: inout Set<String>) -> String {
        let defaultName = defaultName(for: sourceURL)
        let stem = URL(fileURLWithPath: defaultName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: defaultName).pathExtension
        var candidate = defaultName
        var suffix = 2

        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }

        usedNames.insert(candidate.lowercased())
        return candidate
    }
}

private struct EmptyDetectionState: View {
    let isChecking: Bool
    let hasImage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if isChecking { return "Checking" }
        return hasImage ? "No boxes yet" : "Open, paste, or drop an image"
    }

    private var icon: String {
        if isChecking { return "hourglass" }
        return hasImage ? "viewfinder" : "photo"
    }

    private var message: String {
        if isChecking { return "On-device detection is running." }
        return hasImage
            ? "Scan runs automatically on import. Draw a manual box if anything sensitive was missed."
            : "Supports PNG, JPEG, TIFF, and HEIC. Redaktr flags likely emails, tokens, account IDs, faces, and QR codes before screenshots go into AI chat, Slack, email, tickets, or docs. No account or server."
    }
}

private struct EmptyFilterState: View {
    let filter: FindingFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No \(filter.displayName.lowercased()) findings", systemImage: "line.3.horizontal.decrease.circle")
                .font(.callout.weight(.semibold))
            Text("Switch filters to review the rest of the scan results.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No \(filter.displayName.lowercased()) findings")
        .accessibilityIdentifier("empty-filter-state")
    }
}

private struct PreviewOutputBanner: View {
    var body: some View {
        Label("Output preview", systemImage: "eye.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Output preview")
            .accessibilityIdentifier("preview-output-banner")
            .accessibilityHint("This is the flattened image Copy and Export will produce.")
    }
}

private struct CompletionBanner: View {
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("completion-banner-action-button")
            }

            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("completion-banner-secondary-action-button")
            }
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
        .accessibilityIdentifier("completion-banner")
    }
}

private struct AmbientModePill: View {
    let title: String
    let systemImage: String
    let accessibilityID: String
    let hint: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.16), lineWidth: 1))
            .accessibilityIdentifier(accessibilityID)
            .accessibilityHint(hint)
    }
}

private struct TopToolbarControlModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    let width: CGFloat?

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, width == nil ? 14 : 0)
            .frame(width: width, height: RedaktrUI.controlHeight)
            .background(RedaktrUI.controlSurface, in: RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius).stroke(RedaktrUI.neutralBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: RedaktrUI.cornerRadius))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private enum ToolbarPopover {
    case capture
    case more
}

private extension View {
    func topToolbarControl(width: CGFloat? = nil) -> some View {
        modifier(TopToolbarControlModifier(width: width))
    }
}

private extension DetectionKind {
    var displayName: String {
        switch self {
        case .apiKey: return "API key"
        case .barcode: return "Visual code"
        case .creditCard: return "Payment"
        case .email: return "Email"
        case .face: return "Face"
        case .ipAddress: return "IP address"
        case .phoneNumber: return "Phone"
        case .secret: return "Secret"
        case .unknown: return "Other"
        case .url: return "URL"
        }
    }
}

private extension DetectionBoundsPrecision {
    var displayName: String {
        switch self {
        case .tight: return "Tight"
        case .lineFallback: return "Line"
        case .manual: return "Manual"
        case .unknown: return "Unknown"
        }
    }
}
