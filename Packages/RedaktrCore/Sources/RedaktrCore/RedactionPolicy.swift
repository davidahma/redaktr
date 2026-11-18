import Foundation

public enum RedactionPolicyPackID: String, CaseIterable, Codable, Hashable, Sendable {
    case pii
    case secrets
    case companyConfidential
    case customerAccount
    case custom
}

public enum RedactionPolicyDisposition: String, CaseIterable, Codable, Sendable {
    case autoRedact
    case needsReview
    case ignore

    public var displayName: String {
        switch self {
        case .autoRedact:
            return "Redact"
        case .needsReview:
            return "Review"
        case .ignore:
            return "Off"
        }
    }

    public var summary: String {
        switch self {
        case .autoRedact:
            return "Included in cleaned output automatically."
        case .needsReview:
            return "Flagged for review before sharing."
        case .ignore:
            return "Does not create new findings."
        }
    }

    public var suggestedAction: DetectionSuggestedAction {
        switch self {
        case .autoRedact:
            .redact
        case .needsReview:
            .review
        case .ignore:
            .ignore
        }
    }

    public init(suggestedAction: DetectionSuggestedAction) {
        switch suggestedAction {
        case .redact:
            self = .autoRedact
        case .review:
            self = .needsReview
        case .ignore:
            self = .ignore
        }
    }
}

public struct RedactionPolicyPack: Identifiable, Equatable, Sendable {
    public let id: RedactionPolicyPackID
    public let title: String
    public let summary: String
    public let defaultDisposition: RedactionPolicyDisposition
    public let detectorLabels: [String]

    public init(
        id: RedactionPolicyPackID,
        title: String,
        summary: String,
        defaultDisposition: RedactionPolicyDisposition,
        detectorLabels: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.defaultDisposition = defaultDisposition
        self.detectorLabels = detectorLabels
    }
}

public enum RedactionPolicyPresetID: String, CaseIterable, Codable, Hashable, Sendable {
    case safeSharing
    case developerDevOps
    case supportCustomerData
    case finance
    case healthcareRegulated
    case companyConfidential
    case custom

    public static func normalized(rawValue: String?) -> RedactionPolicyPresetID? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let id = RedactionPolicyPresetID(rawValue: rawValue) {
            return id
        }

        switch rawValue {
        case "aiSharing", "publicDocs":
            return .safeSharing
        case "supportTicket":
            return .supportCustomerData
        case "internalTeammateSharing":
            return .custom
        default:
            return nil
        }
    }
}

public struct RedactionPolicyPreset: Identifiable, Equatable, Sendable {
    public let id: RedactionPolicyPresetID
    public let title: String
    public let summary: String
    public let policyDispositions: [RedactionPolicyPackID: RedactionPolicyDisposition]

    public init(
        id: RedactionPolicyPresetID,
        title: String,
        summary: String,
        policyDispositions: [RedactionPolicyPackID: RedactionPolicyDisposition]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.policyDispositions = policyDispositions
    }
}

public struct RedactionPolicyConfiguration: Codable, Equatable, Sendable {
    public static let currentDefaults = RedactionPolicyConfiguration(dispositions: [:])

    private var dispositionsByPolicyID: [String: RedactionPolicyDisposition]

    public init(dispositions: [RedactionPolicyPackID: RedactionPolicyDisposition] = [:]) {
        dispositionsByPolicyID = Dictionary(
            uniqueKeysWithValues: dispositions.map { ($0.key.rawValue, $0.value) }
        )
    }

    public init(preset: RedactionPolicyPresetID) {
        self.init(dispositions: RedactionPolicyCatalog.preset(preset).policyDispositions)
    }

    public init(presetRawValue: String?) {
        guard let preset = RedactionPolicyPresetID.normalized(rawValue: presetRawValue) else {
            self = .currentDefaults
            return
        }

        self.init(preset: preset)
    }

    public var dispositions: [RedactionPolicyPackID: RedactionPolicyDisposition] {
        dispositionsByPolicyID.reduce(into: [:]) { result, entry in
            guard let id = RedactionPolicyPackID(rawValue: entry.key) else { return }
            result[id] = entry.value
        }
    }

    public func disposition(for policyPackID: RedactionPolicyPackID) -> RedactionPolicyDisposition? {
        dispositionsByPolicyID[policyPackID.rawValue]
    }

    public func suggestedAction(
        for policyPackID: RedactionPolicyPackID,
        defaultAction: DetectionSuggestedAction
    ) -> DetectionSuggestedAction {
        disposition(for: policyPackID)?.suggestedAction ?? defaultAction
    }
}

public enum RedactionPolicyCatalog {
    public static let packs: [RedactionPolicyPack] = [
        RedactionPolicyPack(
            id: .pii,
            title: "PII",
            summary: "Visible personal data such as emails, phone numbers, and payment-card-like values.",
            defaultDisposition: .autoRedact,
            detectorLabels: ["Email", "Phone number", "Card number"]
        ),
        RedactionPolicyPack(
            id: .secrets,
            title: "Secrets/API keys",
            summary: "Visible credentials, API keys, tokens, private URL parameters, and random-looking secrets.",
            defaultDisposition: .autoRedact,
            detectorLabels: [
                "AWS key",
                "GitHub token",
                "Stripe secret key",
                "Bearer token",
                "JWT",
                "Environment secret",
                "URL query token",
                "Google API key",
                "OpenAI API key",
                "Slack token",
                "High-entropy secret"
            ]
        ),
        RedactionPolicyPack(
            id: .companyConfidential,
            title: "Company confidential",
            summary: "Visible confidentiality labels such as Confidential, Internal Only, Do Not Share, NDA, Proprietary, or Restricted.",
            defaultDisposition: .needsReview,
            detectorLabels: ["Confidential label"]
        ),
        RedactionPolicyPack(
            id: .customerAccount,
            title: "Customer/account data",
            summary: "Visible customer, account, tenant, workspace, infrastructure, or account-linking values.",
            defaultDisposition: .needsReview,
            detectorLabels: ["Account/customer ID", "IP address"]
        ),
        RedactionPolicyPack(
            id: .custom,
            title: "Custom terms/regexes",
            summary: "Local terms and regexes configured on this Mac.",
            defaultDisposition: .autoRedact,
            detectorLabels: ["Custom term", "Custom pattern"]
        )
    ]

    public static let presets: [RedactionPolicyPreset] = RedactionPolicyPresetID.allCases.map(preset)

    public static func pack(_ id: RedactionPolicyPackID) -> RedactionPolicyPack {
        packs.first { $0.id == id }!
    }

    public static func preset(_ id: RedactionPolicyPresetID) -> RedactionPolicyPreset {
        switch id {
        case .safeSharing:
            RedactionPolicyPreset(
                id: id,
                title: "Safe Sharing",
                summary: "Balanced default for screenshots going into AI tools, chat, email, tickets, docs, or support threads.",
                policyDispositions: [
                    .pii: .autoRedact,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .autoRedact
                ]
            )
        case .developerDevOps:
            RedactionPolicyPreset(
                id: id,
                title: "Developer/DevOps",
                summary: "Stronger coverage for API keys, auth headers, signed URLs, SSH/JWTs, cloud tokens, kubeconfig, and database secrets while reviewing infrastructure context.",
                policyDispositions: [
                    .pii: .needsReview,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        case .supportCustomerData:
            RedactionPolicyPreset(
                id: id,
                title: "Support/Customer Data",
                summary: "Keeps customer/account context reviewable while redacting secrets and reviewing personal data.",
                policyDispositions: [
                    .pii: .needsReview,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        case .finance:
            RedactionPolicyPreset(
                id: id,
                title: "Finance",
                summary: "Redacts payment-card-like values and secrets, reviews customer/account context and custom finance terms.",
                policyDispositions: [
                    .pii: .autoRedact,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        case .healthcareRegulated:
            RedactionPolicyPreset(
                id: id,
                title: "Healthcare/Regulated",
                summary: "Redacts personal data and secrets, reviews confidential labels and account context for regulated sharing.",
                policyDispositions: [
                    .pii: .autoRedact,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        case .companyConfidential:
            RedactionPolicyPreset(
                id: id,
                title: "Company Confidential",
                summary: "Reviews visible confidential labels and custom company terms without claiming semantic classification.",
                policyDispositions: [
                    .pii: .needsReview,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        case .custom:
            RedactionPolicyPreset(
                id: id,
                title: "Custom",
                summary: "Starts from conservative local defaults and lets your detector settings, terms, regexes, and allowlist define behavior.",
                policyDispositions: [
                    .pii: .needsReview,
                    .secrets: .autoRedact,
                    .companyConfidential: .needsReview,
                    .customerAccount: .needsReview,
                    .custom: .needsReview
                ]
            )
        }
    }

    public static func pack(forDetectorLabel detectorLabel: String) -> RedactionPolicyPack? {
        packs.first { pack in
            pack.detectorLabels.contains(detectorLabel)
        }
    }
}

public enum DetectorTaxonomyGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case secrets
    case personalData
    case financialData
    case governmentIDs
    case companyConfidential
    case visualContent
    case customPolicy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .secrets:
            return "Secrets"
        case .personalData:
            return "Personal data"
        case .financialData:
            return "Financial data"
        case .governmentIDs:
            return "Government IDs"
        case .companyConfidential:
            return "Company confidential"
        case .visualContent:
            return "Visual content"
        case .customPolicy:
            return "Custom policy"
        }
    }

    public var defaultDisposition: RedactionPolicyDisposition {
        switch self {
        case .secrets, .financialData, .governmentIDs:
            return .autoRedact
        case .personalData, .companyConfidential, .visualContent, .customPolicy:
            return .needsReview
        }
    }
}

public struct DetectorCatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let taxonomyGroup: DetectorTaxonomyGroup
    public let defaultDisposition: RedactionPolicyDisposition
    public let implemented: Bool
    public let aliases: [String]

    public init(
        id: String,
        label: String,
        taxonomyGroup: DetectorTaxonomyGroup,
        defaultDisposition: RedactionPolicyDisposition,
        implemented: Bool,
        aliases: [String] = []
    ) {
        self.id = id
        self.label = label
        self.taxonomyGroup = taxonomyGroup
        self.defaultDisposition = defaultDisposition
        self.implemented = implemented
        self.aliases = aliases
    }
}

public enum DetectorCatalog {
    public static let entries: [DetectorCatalogEntry] = [
        DetectorCatalogEntry(id: "aws-key", label: "AWS key", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "github-token", label: "GitHub token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "stripe-secret-key", label: "Stripe secret key", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "bearer-token", label: "Bearer token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true, aliases: ["Authorization header"]),
        DetectorCatalogEntry(id: "jwt", label: "JWT", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "ssh-public-key", label: "SSH public key", taxonomyGroup: .secrets, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "environment-secret", label: "Environment secret", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "url-query-token", label: "URL query token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true, aliases: ["Signed URL token", "Magic/reset link token"]),
        DetectorCatalogEntry(id: "google-api-key", label: "Google API key", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "openai-api-key", label: "OpenAI API key", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "slack-token", label: "Slack token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "high-entropy-secret", label: "High-entropy secret", taxonomyGroup: .secrets, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "email", label: "Email", taxonomyGroup: .personalData, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "phone-number", label: "Phone number", taxonomyGroup: .personalData, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "card-number", label: "Card number", taxonomyGroup: .financialData, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "ip-address", label: "IP address", taxonomyGroup: .personalData, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "account-customer-id", label: "Account/customer ID", taxonomyGroup: .companyConfidential, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "confidential-label", label: "Confidential label", taxonomyGroup: .companyConfidential, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "qr-barcode", label: "QR/barcode", taxonomyGroup: .visualContent, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "face", label: "Face", taxonomyGroup: .visualContent, defaultDisposition: .needsReview, implemented: true),
        DetectorCatalogEntry(id: "custom-term", label: "Custom term", taxonomyGroup: .customPolicy, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "custom-pattern", label: "Custom pattern", taxonomyGroup: .customPolicy, defaultDisposition: .autoRedact, implemented: true),
        DetectorCatalogEntry(id: "government-id", label: "Government ID", taxonomyGroup: .governmentIDs, defaultDisposition: .autoRedact, implemented: false, aliases: ["SSN", "passport", "driver license"]),
        DetectorCatalogEntry(id: "session-cookie", label: "Session cookie", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false),
        DetectorCatalogEntry(id: "cloud-credential", label: "Cloud credential", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false, aliases: ["GCP", "Azure"]),
        DetectorCatalogEntry(id: "package-registry-token", label: "Package registry token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false, aliases: ["npm", "PyPI", "Docker"]),
        DetectorCatalogEntry(id: "webhook-url", label: "Webhook URL", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false),
        DetectorCatalogEntry(id: "kubeconfig-service-account", label: "Kubeconfig/service-account token", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false),
        DetectorCatalogEntry(id: "terraform-secret", label: "Terraform state/vars secret", taxonomyGroup: .secrets, defaultDisposition: .autoRedact, implemented: false),
        DetectorCatalogEntry(id: "meeting-link", label: "Meeting link", taxonomyGroup: .companyConfidential, defaultDisposition: .needsReview, implemented: false, aliases: ["Zoom", "Meet", "Webex"]),
        DetectorCatalogEntry(id: "generic-domain", label: "Generic domain", taxonomyGroup: .companyConfidential, defaultDisposition: .ignore, implemented: false),
        DetectorCatalogEntry(id: "person-name", label: "Person name", taxonomyGroup: .personalData, defaultDisposition: .ignore, implemented: false),
        DetectorCatalogEntry(id: "date", label: "Date", taxonomyGroup: .personalData, defaultDisposition: .ignore, implemented: false),
        DetectorCatalogEntry(id: "location", label: "Location", taxonomyGroup: .personalData, defaultDisposition: .ignore, implemented: false),
        DetectorCatalogEntry(id: "broad-numeric-identifier", label: "Broad numeric identifier", taxonomyGroup: .companyConfidential, defaultDisposition: .ignore, implemented: false, aliases: ["Loose number", "Spreadsheet number"])
    ]

    public static func entry(forLabel label: String) -> DetectorCatalogEntry? {
        entries.first { $0.label == label }
    }
}

public enum LearnedSafeRuleScope: Equatable, Codable, Sendable {
    case global
    case folder(String)
    case project(String)
    case domain(String)

    enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    enum Kind: String, Codable {
        case global
        case folder
        case project
        case domain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        switch kind {
        case .global:
            self = .global
        case .folder:
            self = .folder(value ?? "")
        case .project:
            self = .project(value ?? "")
        case .domain:
            self = .domain(value ?? "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode(Kind.global, forKey: .kind)
        case .folder(let value):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .project(let value):
            try container.encode(Kind.project, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .domain(let value):
            try container.encode(Kind.domain, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct LearnedSafeRule: Identifiable, Equatable, Codable, Sendable {
    public enum MatchKind: String, Codable, Sendable {
        case exactText
        case pattern
    }

    public var id: String
    public var matchKind: MatchKind
    public var value: String
    public var detectorLabel: String?
    public var scope: LearnedSafeRuleScope

    public init(
        id: String = UUID().uuidString,
        matchKind: MatchKind = .exactText,
        value: String,
        detectorLabel: String? = nil,
        scope: LearnedSafeRuleScope = .global
    ) {
        self.id = id
        self.matchKind = matchKind
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detectorLabel = detectorLabel
        self.scope = scope
    }

    public func matches(_ candidate: String, detectorLabel: String?) -> Bool {
        if let selfDetectorLabel = self.detectorLabel,
           let detectorLabel,
           selfDetectorLabel != detectorLabel {
            return false
        }

        switch matchKind {
        case .exactText:
            return Self.normalized(candidate) == Self.normalized(value)
        case .pattern:
            return (try? NSRegularExpression(pattern: value))
                .map { regex in
                    let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                    return regex.firstMatch(in: candidate, range: range) != nil
                } ?? false
        }
    }

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct DetectorBacklogItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let priority: Int
    public let taxonomyGroup: DetectorTaxonomyGroup
    public let defaultDisposition: RedactionPolicyDisposition
    public let requiresFixturesBeforeDefault: Bool
}

public enum DetectorBacklog {
    public static let highValueItems: [DetectorBacklogItem] = [
        DetectorBacklogItem(id: "session-cookies", label: "Session cookies", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "magic-reset-links", label: "Magic/reset links", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "signed-cloud-urls", label: "Signed cloud URLs", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "gcp-azure-credentials", label: "GCP/Azure credentials", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "registry-tokens", label: "npm/PyPI/Docker/GitLab registry tokens", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "observability-tokens", label: "Datadog/Sentry/Twilio/SendGrid tokens", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "kubeconfig-service-account", label: "Kubeconfig/service-account tokens", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "terraform-state-vars", label: "Terraform state/vars secrets", priority: 1, taxonomyGroup: .secrets, defaultDisposition: .autoRedact, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "meeting-links", label: "Meeting links", priority: 3, taxonomyGroup: .companyConfidential, defaultDisposition: .needsReview, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "generic-domains", label: "Generic domains", priority: 3, taxonomyGroup: .companyConfidential, defaultDisposition: .ignore, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "person-names", label: "Person names", priority: 4, taxonomyGroup: .personalData, defaultDisposition: .ignore, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "dates", label: "Dates", priority: 4, taxonomyGroup: .personalData, defaultDisposition: .ignore, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "locations", label: "Locations", priority: 4, taxonomyGroup: .personalData, defaultDisposition: .ignore, requiresFixturesBeforeDefault: true),
        DetectorBacklogItem(id: "broad-numeric-identifiers", label: "Broad numeric identifiers", priority: 4, taxonomyGroup: .companyConfidential, defaultDisposition: .ignore, requiresFixturesBeforeDefault: true)
    ]
}

public struct PolicyActionExplanation: Equatable, Sendable {
    public let label: String
    public let detail: String

    public init(entry: RedactionPlanEntry) {
        let detection = entry.detection
        let pack = RedactionPolicyCatalog.pack(forDetectorLabel: detection.label)
        let detectorName = detection.label
        let packName = pack?.title ?? DetectorCatalog.entry(forLabel: detectorName)?.taxonomyGroup.displayName ?? "detector"

        if !entry.isActive {
            if detection.suggestedAction == .ignore {
                label = "Off by policy"
                detail = "\(detectorName) is ignored for the active \(packName) policy."
            } else {
                label = "Turned off"
                detail = "\(detectorName) was turned off by the user and will not be included in cleaned output."
            }
            return
        }

        switch detection.suggestedAction {
        case .redact:
            label = "Auto-redacted"
            detail = "\(detectorName) matched \(packName); policy includes it in cleaned output."
        case .review:
            label = "Needs review"
            detail = "\(detectorName) matched \(packName); policy keeps it included but asks you to confirm it before sharing."
        case .ignore:
            label = "Included manually"
            detail = "\(detectorName) is included even though the active policy would normally ignore it."
        }
    }

    public var displayText: String {
        "\(label): \(detail)"
    }
}
