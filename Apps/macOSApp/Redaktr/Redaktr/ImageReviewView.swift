import AppKit
import RedaktrCore
import SwiftUI

struct ImageReviewView: View {
    let image: NSImage
    @Binding var redactionPlan: RedactionPlan
    @Binding var selectedDetectionID: Detection.ID?
    @Binding var isManualEditing: Bool
    let isPreviewingRedactedOutput: Bool
    let keepsManualEditingAfterCommit: Bool
    let onPlanChanged: () -> Void
    let onManualEditCommitted: (RedactionPlan, RedactionPlan) -> Void

    @State private var draftBounds: CGRect?
    @State private var moveStartBounds: CGRect?
    @State private var resizeStartBounds: CGRect?
    @State private var manualEditStartPlan: RedactionPlan?
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var panStartOffset: CGSize?
    @State private var hoveredDetectionID: Detection.ID?

    var body: some View {
        GeometryReader { proxy in
            let imageSize = image.size
            let fitted = RedactionGeometry.fittedRect(for: imageSize, in: proxy.size)
            let viewport = viewportRect(for: fitted)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Image(nsImage: image)
                    .resizable()
                    .frame(width: viewport.width, height: viewport.height)
                    .offset(x: viewport.minX, y: viewport.minY)

                if !isManualEditing, zoomScale > 1 {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .gesture(panGesture(fittedRect: fitted))
                }

                if !isPreviewingRedactedOutput {
                    ForEach(redactionPlan.entries) { entry in
                        let detection = entry.detection
                        let rect = RedactionGeometry.displayRect(
                            for: detection.normalizedBounds,
                            imageSize: imageSize,
                            fittedRect: viewport
                        )

                        detectionOverlay(for: entry, displayRect: rect, fittedRect: viewport)
                    }
                }

                if !isPreviewingRedactedOutput, isManualEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: viewport.width, height: viewport.height)
                        .offset(x: viewport.minX, y: viewport.minY)
                        .gesture(drawGesture(fittedRect: viewport))
                }

                if let draftBounds {
                    let rect = RedactionGeometry.displayRect(for: draftBounds, imageSize: imageSize, fittedRect: viewport)

                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .overlay(alignment: .top) {
                zoomControls(fittedRect: fitted)
                    .padding(10)
            }
            .onChange(of: selectedDetectionID) { _, selectedID in
                focusDetection(selectedID, fittedRect: fitted)
            }
        }
        .onChange(of: image.size) { _, _ in
            resetViewport()
        }
    }

    private func detectionOverlay(
        for entry: RedactionPlanEntry,
        displayRect rect: CGRect,
        fittedRect: CGRect
    ) -> some View {
        let isSelected = selectedDetectionID == entry.id

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    strokeColor(for: entry, isSelected: isSelected),
                    style: StrokeStyle(
                        lineWidth: isSelected ? 3 : (entry.isActive ? 3 : 2),
                        dash: entry.isActive ? [] : [6, 4]
                    )
                )
                .background(
                    fillColor(for: entry).opacity(entry.isActive ? 0.16 : 0.08),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
                .gesture(moveGesture(for: entry, fittedRect: fittedRect))

            if shouldShowLabel(for: entry) {
                Text(overlayLabel(for: entry))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.86), in: Capsule())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .offset(y: labelYOffset(for: rect))
                    .accessibilityHidden(true)
            }

            if isSelected, !isManualEditing {
                ForEach(ResizeCorner.allCases) { corner in
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .position(corner.position(in: rect.size))
                        .gesture(resizeGesture(for: entry, corner: corner, fittedRect: fittedRect))
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDetectionID = entry.id
            isManualEditing = false
            onPlanChanged()
        }
        .onHover { isHovering in
            hoveredDetectionID = isHovering ? entry.id : nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.detection.label)
        .accessibilityValue(overlayAccessibilityValue(for: entry))
        .accessibilityHint("Selects this redaction box for review.")
        .allowsHitTesting(!isManualEditing && !isPreviewingRedactedOutput)
    }

    private func drawGesture(fittedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard isManualEditing, fittedRect.contains(value.startLocation) else {
                    draftBounds = nil
                    return
                }

                draftBounds = normalizedRect(from: value.startLocation, to: value.location, in: fittedRect)
            }
            .onEnded { value in
                defer { draftBounds = nil }
                guard isManualEditing, fittedRect.contains(value.startLocation) else { return }

                let bounds = normalizedRect(from: value.startLocation, to: value.location, in: fittedRect)
                let previousPlan = redactionPlan
                if let id = redactionPlan.addManualRedaction(bounds: bounds) {
                    selectedDetectionID = id
                    isManualEditing = keepsManualEditingAfterCommit
                    onManualEditCommitted(previousPlan, redactionPlan)
                    onPlanChanged()
                }
            }
    }

    private func moveGesture(for entry: RedactionPlanEntry, fittedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard
                    selectedDetectionID == entry.id,
                    !isPreviewingRedactedOutput,
                    !isManualEditing,
                    fittedRect.width > 0,
                    fittedRect.height > 0
                else {
                    return
                }

                if moveStartBounds == nil {
                    moveStartBounds = entry.detection.normalizedBounds
                    manualEditStartPlan = redactionPlan
                }
                guard let moveStartBounds else { return }

                let proposed = CGRect(
                    x: moveStartBounds.minX + value.translation.width / fittedRect.width,
                    y: moveStartBounds.minY - value.translation.height / fittedRect.height,
                    width: moveStartBounds.width,
                    height: moveStartBounds.height
                )
                if redactionPlan.updateRedactionBounds(id: entry.id, bounds: clampedMovingBounds(proposed)) {
                    onPlanChanged()
                }
            }
            .onEnded { _ in
                if let manualEditStartPlan {
                    onManualEditCommitted(manualEditStartPlan, redactionPlan)
                }
                moveStartBounds = nil
                manualEditStartPlan = nil
                onPlanChanged()
            }
    }

    private func resizeGesture(
        for entry: RedactionPlanEntry,
        corner: ResizeCorner,
        fittedRect: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard
                    selectedDetectionID == entry.id,
                    !isPreviewingRedactedOutput,
                    !isManualEditing,
                    fittedRect.width > 0,
                    fittedRect.height > 0
                else {
                    return
                }

                if resizeStartBounds == nil {
                    resizeStartBounds = entry.detection.normalizedBounds
                    manualEditStartPlan = redactionPlan
                }
                guard let resizeStartBounds else { return }

                let proposed = resizedBounds(
                    from: resizeStartBounds,
                    translation: value.translation,
                    corner: corner,
                    fittedRect: fittedRect
                )
                if redactionPlan.updateRedactionBounds(id: entry.id, bounds: proposed) {
                    onPlanChanged()
                }
            }
            .onEnded { _ in
                if let manualEditStartPlan {
                    onManualEditCommitted(manualEditStartPlan, redactionPlan)
                }
                resizeStartBounds = nil
                manualEditStartPlan = nil
                onPlanChanged()
            }
    }

    private func strokeColor(for entry: RedactionPlanEntry, isSelected: Bool) -> Color {
        if isSelected { return .accentColor }
        if !entry.isActive { return .secondary }
        if entry.detection.suggestedAction == .review
            || entry.detection.confidence < 0.8
            || entry.detection.boundsPrecision == .lineFallback {
            return .orange
        }
        return .accentColor
    }

    private func fillColor(for entry: RedactionPlanEntry) -> Color {
        guard entry.isActive else { return .secondary }

        if entry.detection.suggestedAction == .review
            || entry.detection.confidence < 0.8
            || entry.detection.boundsPrecision == .lineFallback {
            return .orange
        }
        return .accentColor
    }

    private func overlayLabel(for entry: RedactionPlanEntry) -> String {
        "\(entry.detection.label) - \(overlayStateText(for: entry))"
    }

    private func shouldShowLabel(for entry: RedactionPlanEntry) -> Bool {
        selectedDetectionID == entry.id || hoveredDetectionID == entry.id
    }

    private func labelYOffset(for rect: CGRect) -> CGFloat {
        rect.minY < 28 ? rect.height + 4 : -24
    }

    private func overlayStateText(for entry: RedactionPlanEntry) -> String {
        guard entry.isActive else { return "Visible" }

        if entry.detection.suggestedAction == .review
            || entry.detection.confidence < 0.8
            || entry.detection.boundsPrecision == .lineFallback {
            return "Check"
        }

        return "Redact"
    }

    private func overlayAccessibilityValue(for entry: RedactionPlanEntry) -> String {
        let exportState = entry.isActive ? "Will redact in export" : "Visible in export"
        let confidence = Int((entry.detection.confidence * 100).rounded())
        return "\(exportState). \(overlayStateText(for: entry)). \(confidence) percent confidence."
    }

    private func zoomControls(fittedRect: CGRect) -> some View {
        HStack(spacing: 6) {
            Button {
                setZoomScale(zoomScale / 1.25, fittedRect: fittedRect)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomScale <= 1)
            .help("Zoom out")
            .accessibilityLabel("Zoom out")
            .accessibilityIdentifier("zoom-out-button")

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 46)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Zoom")
                .accessibilityValue("\(Int((zoomScale * 100).rounded())) percent")
                .accessibilityIdentifier("zoom-percent-label")

            Button {
                setZoomScale(zoomScale * 1.25, fittedRect: fittedRect)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomScale >= 4)
            .help("Zoom in")
            .accessibilityLabel("Zoom in")
            .accessibilityIdentifier("zoom-in-button")

            Button {
                resetViewport()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .help("Fit image")
            .accessibilityLabel("Fit image")
            .accessibilityIdentifier("fit-image-button")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier("zoom-controls")
    }

    private func viewportRect(for fittedRect: CGRect) -> CGRect {
        let size = CGSize(width: fittedRect.width * zoomScale, height: fittedRect.height * zoomScale)
        let offset = clampedPanOffset(panOffset, fittedRect: fittedRect, zoomScale: zoomScale)

        return CGRect(
            x: fittedRect.midX - size.width / 2 + offset.width,
            y: fittedRect.midY - size.height / 2 + offset.height,
            width: size.width,
            height: size.height
        )
    }

    private func setZoomScale(_ scale: CGFloat, fittedRect: CGRect) {
        withAnimation(.easeInOut(duration: 0.12)) {
            zoomScale = min(max(scale, 1), 4)
            panOffset = clampedPanOffset(panOffset, fittedRect: fittedRect, zoomScale: zoomScale)
        }
    }

    private func resetViewport() {
        withAnimation(.easeInOut(duration: 0.12)) {
            zoomScale = 1
            panOffset = .zero
            panStartOffset = nil
        }
    }

    private func focusDetection(_ id: Detection.ID?, fittedRect: CGRect) {
        guard
            let id,
            let entry = redactionPlan.entries.first(where: { $0.id == id }),
            fittedRect.width > 0,
            fittedRect.height > 0
        else {
            return
        }

        let targetZoom = max(zoomScale, 1.6)
        let bounds = entry.detection.normalizedBounds
        let displayedCenterY = 1 - bounds.midY
        let proposedOffset = CGSize(
            width: fittedRect.width * targetZoom * (0.5 - bounds.midX),
            height: fittedRect.height * targetZoom * (0.5 - displayedCenterY)
        )

        withAnimation(.easeInOut(duration: 0.16)) {
            zoomScale = min(max(targetZoom, 1), 4)
            panOffset = clampedPanOffset(proposedOffset, fittedRect: fittedRect, zoomScale: zoomScale)
            panStartOffset = nil
        }
    }

    private func panGesture(fittedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStartOffset == nil {
                    panStartOffset = panOffset
                }

                let start = panStartOffset ?? .zero
                let proposed = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                panOffset = clampedPanOffset(proposed, fittedRect: fittedRect, zoomScale: zoomScale)
            }
            .onEnded { _ in
                panOffset = clampedPanOffset(panOffset, fittedRect: fittedRect, zoomScale: zoomScale)
                panStartOffset = nil
            }
    }

    private func clampedPanOffset(_ offset: CGSize, fittedRect: CGRect, zoomScale: CGFloat) -> CGSize {
        guard zoomScale > 1 else { return .zero }

        let maxX = fittedRect.width * (zoomScale - 1) / 2
        let maxY = fittedRect.height * (zoomScale - 1) / 2

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint, in fittedRect: CGRect) -> CGRect {
        let first = normalizedPoint(start, in: fittedRect)
        let second = normalizedPoint(end, in: fittedRect)

        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }

    private func normalizedPoint(_ point: CGPoint, in fittedRect: CGRect) -> CGPoint {
        guard fittedRect.width > 0, fittedRect.height > 0 else { return .zero }

        let x = min(max(point.x, fittedRect.minX), fittedRect.maxX)
        let y = min(max(point.y, fittedRect.minY), fittedRect.maxY)

        return CGPoint(
            x: (x - fittedRect.minX) / fittedRect.width,
            y: 1 - ((y - fittedRect.minY) / fittedRect.height)
        )
    }

    private func clampedMovingBounds(_ bounds: CGRect) -> CGRect {
        let rect = bounds.standardized
        let width = min(rect.width, 1)
        let height = min(rect.height, 1)
        let x = min(max(rect.minX, 0), 1 - width)
        let y = min(max(rect.minY, 0), 1 - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func resizedBounds(
        from bounds: CGRect,
        translation: CGSize,
        corner: ResizeCorner,
        fittedRect: CGRect
    ) -> CGRect {
        let minimumDimension: CGFloat = 0.002
        let dx = translation.width / fittedRect.width
        let dy = -translation.height / fittedRect.height
        var minX = bounds.minX
        var maxX = bounds.maxX
        var minY = bounds.minY
        var maxY = bounds.maxY

        if corner.movesMinX {
            minX += dx
        } else {
            maxX += dx
        }

        if corner.movesMinY {
            minY += dy
        } else {
            maxY += dy
        }

        minX = min(max(minX, 0), 1)
        maxX = min(max(maxX, 0), 1)
        minY = min(max(minY, 0), 1)
        maxY = min(max(maxY, 0), 1)

        if maxX - minX < minimumDimension {
            if corner.movesMinX {
                minX = max(0, maxX - minimumDimension)
            } else {
                maxX = min(1, minX + minimumDimension)
            }
        }

        if maxY - minY < minimumDimension {
            if corner.movesMinY {
                minY = max(0, maxY - minimumDimension)
            } else {
                maxY = min(1, minY + minimumDimension)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private enum ResizeCorner: CaseIterable, Identifiable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: Self { self }

    var movesMinX: Bool {
        self == .topLeading || self == .bottomLeading
    }

    var movesMinY: Bool {
        self == .bottomLeading || self == .bottomTrailing
    }

    func position(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeading:
            return CGPoint(x: 0, y: 0)
        case .topTrailing:
            return CGPoint(x: size.width, y: 0)
        case .bottomLeading:
            return CGPoint(x: 0, y: size.height)
        case .bottomTrailing:
            return CGPoint(x: size.width, y: size.height)
        }
    }
}

struct DropTargetView: View {
    let onOpenImage: () -> Void
    let onPasteImage: () -> Void
    let onCaptureArea: () -> Void
    let onOpenBatch: () -> Void
    @AppStorage(RedaktrOnboardingStorage.didDismissGettingStartedKey) private var didDismissGettingStarted = false
    @State private var hidesGettingStartedNow = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop screenshots, images, or a folder")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Redaktr scans on this Mac for likely emails, tokens, account IDs, faces, and QR codes before you export a cleaned copy.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 560)

                    HStack(spacing: RedaktrUI.controlSpacing) {
                        Button(action: onOpenImage) {
                            Label("Open Images", systemImage: "folder")
                        }
                        .buttonStyle(.redaktr(.primary, minWidth: 168))
                        .accessibilityIdentifier("empty-open-image-button")

                        Button(action: onPasteImage) {
                            Label("Paste Image", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.redaktr(.secondary, minWidth: 138))
                        .accessibilityIdentifier("empty-paste-image-button")
                    }

                    HStack(spacing: RedaktrUI.controlSpacing) {
                        Button(action: onCaptureArea) {
                            Label("Capture Area", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.redaktr(.quiet, minWidth: 138))
                        .accessibilityIdentifier("empty-capture-area-button")

                        Button(action: onOpenBatch) {
                            Label("Open Batch or Folder", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(.redaktr(.quiet, minWidth: 190))
                        .accessibilityIdentifier("empty-open-batch-button")
                    }

                    HStack(spacing: 8) {
                        EmptyStateChip(text: "PNG")
                        EmptyStateChip(text: "JPEG")
                        EmptyStateChip(text: "TIFF")
                        EmptyStateChip(text: "HEIC")
                    }

                    if !didDismissGettingStarted && !hidesGettingStartedNow {
                        GettingStartedChecklistView(isCompact: true) {
                            hidesGettingStartedNow = true
                            didDismissGettingStarted = true
                        }
                        .frame(maxWidth: 620)
                        .accessibilityIdentifier("empty-getting-started-checklist")
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .foregroundStyle(.secondary.opacity(0.35))
        )
        .accessibilityElement(children: .contain)
    }
}

private struct EmptyStateChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }
}
