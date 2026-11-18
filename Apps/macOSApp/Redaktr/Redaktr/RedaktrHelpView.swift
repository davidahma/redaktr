import AppKit
import RedaktrCore
import SwiftUI

enum RedaktrOnboardingStorage {
    static let didCompleteKey = "redaktrDidCompleteOnboardingV1"
    static let didDismissGettingStartedKey = "redaktrDidDismissGettingStartedV1"
}

struct RedaktrOnboardingView: View {
    let onFinish: () -> Void
    let onTrySample: () -> Void
    let onOpenHelp: () -> Void

    private let steps = [
        RedaktrGuideItem(
            systemImage: "photo.on.rectangle",
            title: "Open or paste an image",
            detail: "Use Open, Paste, drag-and-drop, or Try Sample. Redaktr scans supported images locally.",
            accessibilityID: "onboarding-step-start"
        ),
        RedaktrGuideItem(
            systemImage: "checklist.checked",
            title: "Review possible leaks",
            detail: "Redact findings are hidden. Check findings are redacted too, but need a closer look before sharing.",
            accessibilityID: "onboarding-step-review"
        ),
        RedaktrGuideItem(
            systemImage: "square.and.arrow.up",
            title: "Copy or export a clean image",
            detail: "Copy a flattened PNG or export a cleaned image. Source files are not changed.",
            accessibilityID: "onboarding-step-export"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Start")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding-quick-start-title")

                    Text("Catch what you're about to leak")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Load one image, review what Redaktr found, then share the cleaned copy. Add capture, folder, and clipboard protection when you want Redaktr in the path before screenshots leave your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onFinish) {
                    Label("Close", systemImage: "xmark.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close onboarding")
                .accessibilityIdentifier("onboarding-close-button")
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    RedaktrGuideRow(item: step)
                }
            }

            HStack(spacing: 10) {
                Button(action: onTrySample) {
                    Label("Try Sample", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding-try-sample-button")

                Button(action: onOpenHelp) {
                    Label("Help Center", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("onboarding-help-button")

                Spacer()

                Button(action: onFinish) {
                    Text("Start Using Redaktr")
                        .frame(minWidth: 132)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Start Using Redaktr")
                .accessibilityIdentifier("onboarding-finish-button")
            }
        }
        .padding(28)
        .frame(width: 680)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-view")
    }
}

enum RedaktrSampleImage {
    enum RenderError: Error {
        case failed
    }

    private static let size = NSSize(width: 1120, height: 720)

    static func cgImage() throws -> CGImage {
        let bitmap = try bitmapRepresentation()
        guard let cgImage = bitmap.cgImage else {
            throw RenderError.failed
        }
        return cgImage
    }

    static func pngData() throws -> Data {
        let bitmap = try bitmapRepresentation()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.failed
        }
        return data
    }

    private static func bitmapRepresentation() throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderError.failed
        }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 56, y: 64, width: 1008, height: 592), xRadius: 18, yRadius: 18).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let codeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]

        draw("Redaktr sample screenshot", x: 96, top: 102, size: size, attributes: titleAttributes)
        draw("Review the highlighted data before sharing this screenshot.", x: 96, top: 154, size: size, attributes: subtitleAttributes)
        draw("$ curl https://api.acme.test/v1/users", x: 96, top: 242, size: size, attributes: codeAttributes)
        draw("aws_secret = AKIAIOSFODNN7EXAMPLE", x: 96, top: 304, size: size, attributes: codeAttributes)
        draw("maya@acme.test", x: 96, top: 366, size: size, attributes: codeAttributes)
        draw("account_id = acct_492038471", x: 96, top: 428, size: size, attributes: codeAttributes)

        context.flushGraphics()
        return bitmap
    }

    private static func draw(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        size: NSSize,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: x, y: size.height - top - textSize.height))
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted = "getting-started"
    case shortcuts
    case detection
    case findingStates = "finding-states"
    case batchReview = "batch-review"
    case manualRedaction = "manual-redaction"
    case customPolicies = "custom-policies"
    case exportCopy = "export-copy"
    case protectionModes = "protection-modes"
    case privacy
    case contact
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .shortcuts: return "Shortcuts"
        case .detection: return "Detection"
        case .findingStates: return "Finding States"
        case .batchReview: return "Batch Review"
        case .manualRedaction: return "Manual Redaction"
        case .customPolicies: return "Custom Terms"
        case .exportCopy: return "Export and Copy"
        case .protectionModes: return "Protection Modes"
        case .privacy: return "Privacy"
        case .contact: return "Contact"
        case .troubleshooting: return "Troubleshooting"
        }
    }

    var sectionAccessibilityID: String {
        "help-\(rawValue)-section"
    }
}

struct RedaktrHelpCenterView: View {
    let onShowQuickStart: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var selectedTopic: HelpTopic = .gettingStarted


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Redaktr Help Center")
                        .font(.title2.weight(.bold))
                    Text("Local screenshot protection, review workflow, and privacy boundaries.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onShowQuickStart) {
                    Label("Quick Start", systemImage: "play.circle")
                }
                .accessibilityLabel("Quick Start")
                .accessibilityIdentifier("quick-start-from-help-button")

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("open-settings-from-help-button")

                Button("Done", action: onClose)
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityLabel("Close Help Center")
                .accessibilityIdentifier("help-center-close-button")
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(HelpTopic.allCases) { topic in
                            Button {
                                selectedTopic = topic
                            } label: {
                                Text(topic.title)
                                    .font(.callout.weight(selectedTopic == topic ? .semibold : .regular))
                                    .foregroundStyle(selectedTopic == topic ? Color.accentColor : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedTopic == topic
                                            ? Color.accentColor.opacity(0.12)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(topic.title)
                            .accessibilityIdentifier("help-nav-\(topic.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("help-navigation-sidebar")
                    .padding(14)
                }
                .frame(width: 176)

                Divider()

                ScrollView {
                    selectedTopicContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(selectedTopic)
            }
        }
        .frame(width: 900, height: 680)
        .onExitCommand(perform: onClose)
        .accessibilityIdentifier("help-center-view")
    }

    @ViewBuilder
    private var selectedTopicContent: some View {
        switch selectedTopic {
        case .gettingStarted:
            HelpTopicSection(topic: .gettingStarted) {
                GettingStartedChecklistView()
                    .accessibilityIdentifier("help-getting-started-checklist")
            }

        case .shortcuts:
            HelpTopicSection(topic: .shortcuts) {
                KeyboardShortcutTableView()
                Text("Capture defaults can be customized or disabled in Settings, Protection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("help-capture-shortcuts-copy")
            }

        case .detection:
            HelpTopicSection(topic: .detection) {
                RedaktrHelpSection(
                    items: [
                        "Emails, phones, cards, IP addresses, URLs, tokens, API keys, high-entropy strings, QR codes, barcodes, faces, and custom terms or regexes.",
                        "Use Settings, Detection to turn detector families on or off for future scans and to see what each family can and cannot catch.",
                        "Confidential protection works on visible labels or configured terms, domains, codenames, customer names, ticket IDs, and account identifiers.",
                        "Redaktr does not promise semantic classification of everything confidential."
                    ]
                )
            }

        case .findingStates:
            HelpTopicSection(topic: .findingStates) {
                FindingStatesLegendView()
            }

        case .batchReview:
            HelpTopicSection(topic: .batchReview) {
                RedaktrHelpSection(
                    items: [
                        "Open multiple images or a folder to scan them as a batch.",
                        "Use the left queue to move through each image, then export the batch to a new Redaktr Cleaned folder.",
                        "The Include safe option controls whether images with no findings are included in the batch export."
                    ]
                )
            }

        case .manualRedaction:
            HelpTopicSection(topic: .manualRedaction) {
                RedaktrHelpSection(
                    items: [
                        "Use Draw for missed content, then drag or resize boxes to tighten bounds.",
                        "Undo and Redo become available after manual changes. Reset applies to adjusted boxes. Delete applies to manual boxes.",
                        "Preview output shows the flattened image that Copy and Export will produce."
                    ]
                )
            }

        case .customPolicies:
            HelpTopicSection(topic: .customPolicies) {
                RedaktrHelpSection(
                    items: [
                        "Use workflow presets such as Safe Sharing, Developer/DevOps, Support/Customer Data, Finance, Healthcare/Regulated, Company Confidential, or Custom.",
                        "Set detector families to Redact, Review, or Off in Settings. Open images re-scan automatically after detection settings change.",
                        "Add terms, regexes, and known-safe strings in Settings for customer names, domains, codenames, labels, and known false positives.",
                        "Use Remember exact text as safe on a selected false positive to add only that matched string to the local allowlist.",
                        "Custom terms match visible OCR text. Redaktr cannot infer hidden context that is not visible in the image."
                    ]
                )
            }

        case .exportCopy:
            HelpTopicSection(topic: .exportCopy) {
                RedaktrHelpSection(
                    items: [
                        "Copy creates a flattened cleaned PNG on the clipboard.",
                        "Export writes a cleaned PNG or JPEG and keeps the original image unchanged.",
                        "Use More, Reveal Last Export to jump back to the most recent cleaned file or batch folder."
                    ]
                )
            }

        case .protectionModes:
            HelpTopicSection(topic: .protectionModes) {
                Text("Screenshot Protection is one local pipeline for the moments screenshots are captured, saved, copied, or pasted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement()
                    .accessibilityIdentifier("help-screenshot-protection-pipeline")

                Text("Use Clipboard Guard and Redaktr Capture before screenshots go into AI chat, Slack, email, support tickets, or docs. Redaktr does not monitor which app you paste into.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement()
                    .accessibilityIdentifier("help-ai-paste-protection")

                RedaktrHelpSection(
                    items: [
                        "Screenshot Watch scans new images after they are saved in a folder you choose.",
                        "Clipboard Protection is opt-in, image-only, and uses AutoClean modes: review first, pause if unsure, or auto-clean everything.",
                        "Redaktr Capture offers area, window, and screen capture with configurable Redaktr-owned shortcuts. It does not intercept Apple's screenshot shortcut before capture.",
                        "Capture Output can review by default, copy a cleaned PNG, save one to a chosen folder, or save and copy; AutoClean can pause for Check findings and every automatic output has Review and Undo."
                    ]
                )
            }

        case .privacy:
            HelpTopicSection(topic: .privacy) {
                RedaktrHelpSection(
                    items: [
                        "Image processing works on this Mac. You can review and export offline.",
                        "This build has no network entitlements, telemetry, or background update checks.",
                        "Safe-share history stores metadata only: timestamp, source type, action, counts, optional output path, and batch count.",
                        "Policy export includes settings only. It does not include history, images, OCR text, or matched sensitive text."
                    ]
                )
            }

        case .contact:
            HelpTopicSection(topic: .contact) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Visit GitHub for documentation, feature suggestions, and private security reporting.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: RedaktrProjectLinks.repository) {
                        Label("Open GitHub Repository", systemImage: "arrow.up.right.square")
                    }
                    .accessibilityIdentifier("help-contact-repository-link")
                }
            }

        case .troubleshooting:
            HelpTopicSection(topic: .troubleshooting) {
                RedaktrHelpSection(
                    items: [
                        "If custom terms do not appear immediately, re-scan or reload the image after saving settings.",
                        "If capture is blocked, check macOS Screen Recording permission for Redaktr.",
                        "If watched screenshots do not appear, reselect the folder so macOS grants access again."
                    ]
                )
            }
        }
    }
}

struct FindingStateHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finding States")
                .font(.headline)

            FindingStatesLegendView(isCompact: true)
        }
        .padding(16)
        .frame(width: 320)
        .accessibilityIdentifier("finding-states-help-popover")
    }
}

private struct RedaktrGuideItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String
    let accessibilityID: String
}

private struct RedaktrGuideRow: View {
    let item: RedaktrGuideItem
    var showsDetail = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.semibold))

                if showsDetail {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(item.accessibilityID)
    }
}

struct GettingStartedChecklistView: View {
    var isCompact = false
    var onDismiss: (() -> Void)?

    private let items = [
        RedaktrGuideItem(
            systemImage: "photo.on.rectangle",
            title: "Open or paste an image",
            detail: "Use Open Images, Paste Image, drag-and-drop, or Capture Area to start.",
            accessibilityID: "getting-started-open-or-paste"
        ),
        RedaktrGuideItem(
            systemImage: "checklist.checked",
            title: "Review the first finding",
            detail: "Check every box and mark anything safe as Visible before sharing.",
            accessibilityID: "getting-started-review-finding"
        ),
        RedaktrGuideItem(
            systemImage: "square.and.arrow.up",
            title: "Export or copy a clean image",
            detail: "Share the cleaned copy. Redaktr does not overwrite the source image.",
            accessibilityID: "getting-started-export-copy"
        ),
        RedaktrGuideItem(
            systemImage: "keyboard",
            title: "Try Redaktr Capture",
            detail: "Use Option-Shift-1 for area, Option-Shift-2 for window, or Option-Shift-3 for screen by default.",
            accessibilityID: "getting-started-capture-shortcuts"
        ),
        RedaktrGuideItem(
            systemImage: "text.badge.checkmark",
            title: "Add a custom term",
            detail: "Add customer names, domains, project codenames, or internal labels in Settings, Detection.",
            accessibilityID: "getting-started-custom-term"
        ),
        RedaktrGuideItem(
            systemImage: "shield.lefthalf.filled",
            title: "Optional: enable Screenshot Protection",
            detail: "Use Capture, Clipboard Guard, and Folder Watch when screenshots should pass through Redaktr before AI chat, Slack, email, tickets, or docs.",
            accessibilityID: "getting-started-protection-modes"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Getting Started")
                        .font(.headline.weight(.bold))
                    Text("A quick path to the first safe share.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onDismiss {
                    Button("Hide", action: onDismiss)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("getting-started-dismiss-button")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayedItems) { item in
                    RedaktrGuideRow(item: item, showsDetail: !isCompact)
                }
            }

            if isCompact {
                Text("More in Help: custom terms, shortcut setup, and optional protection modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("getting-started-more-help-copy")
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("getting-started-checklist")
    }

    private var displayedItems: [RedaktrGuideItem] {
        isCompact ? Array(items.prefix(4)) : items
    }
}

private struct HelpTopicSection<Content: View>: View {
    let topic: HelpTopic
    let content: Content

    init(topic: HelpTopic, @ViewBuilder content: () -> Content) {
        self.topic = topic
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(topic.title)
                .font(.headline.weight(.bold))

            content
        }
        .id(topic.id)
        .accessibilityIdentifier(topic.sectionAccessibilityID)
    }
}

private struct KeyboardShortcutTableView: View {
    private var rows: [ShortcutRow] {
        [
        ShortcutRow(id: "open", action: "Open image or folder", keys: "Command-O"),
        ShortcutRow(id: "close", action: "Close current review", keys: "Command-W"),
        ShortcutRow(id: "paste", action: "Paste image", keys: "Command-Shift-V"),
        ShortcutRow(id: "scan", action: "Scan or re-scan", keys: "Command-D"),
        ShortcutRow(id: "preview", action: "Preview output", keys: "Command-P"),
        ShortcutRow(id: "copy", action: "Copy cleaned PNG", keys: "Command-Shift-C"),
        ShortcutRow(id: "export", action: "Export cleaned image", keys: "Command-E"),
        ShortcutRow(id: "capture-area", action: "Capture area", keys: Self.defaultShortcutText(for: .area)),
        ShortcutRow(id: "capture-window", action: "Capture window", keys: Self.defaultShortcutText(for: .window)),
        ShortcutRow(id: "capture-screen", action: "Capture screen", keys: Self.defaultShortcutText(for: .screen)),
        ShortcutRow(id: "findings", action: "Move findings", keys: "Command-Up / Command-Down"),
        ShortcutRow(id: "toggle", action: "Toggle selected finding", keys: "Space")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.action)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(row.keys)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("help-shortcut-row-\(row.id)")

                if row.id != rows.last?.id {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("help-keyboard-shortcuts-table")
    }

    private static func defaultShortcutText(for mode: RedaktrCaptureMode) -> String {
        mode.defaultShortcutChoice.displayName
    }
}

private struct ShortcutRow: Identifiable {
    let id: String
    let action: String
    let keys: String
}

private struct FindingStatesLegendView: View {
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            FindingStateLegendItem(
                title: "Check",
                detail: "Redaktr will redact it, but inspect the box and bounds before sharing.",
                style: .check
            )
            FindingStateLegendItem(
                title: "Redact",
                detail: "The box will be hidden in copy and export.",
                style: .redact
            )
            FindingStateLegendItem(
                title: "Visible",
                detail: "The content remains visible in cleaned output.",
                style: .visible
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("finding-state-legend")
    }
}

private struct FindingStateLegendItem: View {
    enum Style {
        case check
        case redact
        case visible
    }

    let title: String
    let detail: String
    let style: Style

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            swatch
                .frame(width: 34, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("finding-state-legend-\(title.lowercased())")
    }

    @ViewBuilder
    private var swatch: some View {
        switch style {
        case .check:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                )
        case .redact:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
        case .visible:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.7), lineWidth: 2)
                )
        }
    }
}

private struct RedaktrHelpSection: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 16, height: 18)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
