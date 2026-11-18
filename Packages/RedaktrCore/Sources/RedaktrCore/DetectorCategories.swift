import Foundation

public enum DetectorCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case emails
    case phones
    case cards
    case ipAddresses
    case secrets
    case highEntropy
    case visualCodes
    case faces
    case customerAccount
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .emails: return "Emails"
        case .phones: return "Phones"
        case .cards: return "Cards"
        case .ipAddresses: return "IPs"
        case .secrets: return "Secrets/API keys"
        case .highEntropy: return "High-entropy strings"
        case .visualCodes: return "QR/barcodes"
        case .faces: return "Faces"
        case .customerAccount: return "Customer/account data"
        case .custom: return "Custom terms/regexes"
        }
    }

    public var summary: String {
        switch self {
        case .emails:
            return "Visible email addresses."
        case .phones:
            return "Phone-number-like values with clear formatting, country code, or phone context."
        case .cards:
            return "Payment-card-like numbers that pass Luhn validation."
        case .ipAddresses:
            return "IPv4 addresses visible in screenshots."
        case .secrets:
            return "Known token formats, API keys, bearer tokens, JWTs, URL tokens, and secret-looking environment variables."
        case .highEntropy:
            return "Random-looking strings. Redaktr treats generic matches as Check, not automatic high-confidence redaction."
        case .visualCodes:
            return "QR codes and common barcodes detected locally with Vision."
        case .faces:
            return "Faces detected locally with Vision."
        case .customerAccount:
            return "Visible customer, account, tenant, or workspace identifiers."
        case .custom:
            return "Your local terms, regexes, and visible confidentiality labels."
        }
    }

    public var taxonomyGroup: DetectorTaxonomyGroup {
        switch self {
        case .emails, .phones, .ipAddresses:
            return .personalData
        case .cards:
            return .financialData
        case .secrets, .highEntropy:
            return .secrets
        case .visualCodes, .faces:
            return .visualContent
        case .customerAccount:
            return .companyConfidential
        case .custom:
            return .customPolicy
        }
    }
}

public struct DetectorCategoryPreferences: Codable, Equatable, Sendable {
    public static let allEnabled = DetectorCategoryPreferences()

    public var disabledCategories: Set<DetectorCategory>
    private var categoryDispositionsByID: [String: RedactionPolicyDisposition]
    private var detectorDispositionsByLabel: [String: RedactionPolicyDisposition]

    public init(
        disabledCategories: Set<DetectorCategory> = [],
        categoryDispositions: [DetectorCategory: RedactionPolicyDisposition] = [:],
        detectorDispositions: [String: RedactionPolicyDisposition] = [:]
    ) {
        self.disabledCategories = disabledCategories
        categoryDispositionsByID = Dictionary(
            uniqueKeysWithValues: categoryDispositions.map { ($0.key.rawValue, $0.value) }
        )
        detectorDispositionsByLabel = detectorDispositions
    }

    enum CodingKeys: String, CodingKey {
        case disabledCategories
        case categoryDispositionsByID
        case detectorDispositionsByLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabledCategories = try container.decodeIfPresent(Set<DetectorCategory>.self, forKey: .disabledCategories) ?? []
        categoryDispositionsByID = try container.decodeIfPresent(
            [String: RedactionPolicyDisposition].self,
            forKey: .categoryDispositionsByID
        ) ?? [:]
        detectorDispositionsByLabel = try container.decodeIfPresent(
            [String: RedactionPolicyDisposition].self,
            forKey: .detectorDispositionsByLabel
        ) ?? [:]
    }

    public var categoryDispositions: [DetectorCategory: RedactionPolicyDisposition] {
        categoryDispositionsByID.reduce(into: [:]) { result, entry in
            guard let category = DetectorCategory(rawValue: entry.key) else { return }
            result[category] = entry.value
        }
    }

    public var detectorDispositions: [String: RedactionPolicyDisposition] {
        detectorDispositionsByLabel
    }

    public func isEnabled(_ category: DetectorCategory) -> Bool {
        disposition(for: category) != .ignore
    }

    public func disposition(for category: DetectorCategory) -> RedactionPolicyDisposition? {
        if disabledCategories.contains(category) {
            return .ignore
        }
        return categoryDispositionsByID[category.rawValue]
    }

    public func disposition(forDetectorLabel detectorLabel: String) -> RedactionPolicyDisposition? {
        detectorDispositionsByLabel[detectorLabel]
    }

    public func resolvedDisposition(
        for category: DetectorCategory,
        detectorLabel: String,
        defaultDisposition: RedactionPolicyDisposition
    ) -> RedactionPolicyDisposition {
        disposition(forDetectorLabel: detectorLabel)
            ?? disposition(for: category)
            ?? defaultDisposition
    }

    public mutating func setEnabled(_ isEnabled: Bool, for category: DetectorCategory) {
        if isEnabled {
            disabledCategories.remove(category)
            if categoryDispositionsByID[category.rawValue] == .ignore {
                categoryDispositionsByID.removeValue(forKey: category.rawValue)
            }
        } else {
            disabledCategories.insert(category)
            categoryDispositionsByID[category.rawValue] = .ignore
        }
    }

    public mutating func setDisposition(_ disposition: RedactionPolicyDisposition?, for category: DetectorCategory) {
        disabledCategories.remove(category)
        if let disposition {
            categoryDispositionsByID[category.rawValue] = disposition
            if disposition == .ignore {
                disabledCategories.insert(category)
            }
        } else {
            categoryDispositionsByID.removeValue(forKey: category.rawValue)
        }
    }

    public mutating func setDisposition(_ disposition: RedactionPolicyDisposition?, forDetectorLabel detectorLabel: String) {
        if let disposition {
            detectorDispositionsByLabel[detectorLabel] = disposition
        } else {
            detectorDispositionsByLabel.removeValue(forKey: detectorLabel)
        }
    }
}

public extension Detection {
    var detectorCategory: DetectorCategory {
        switch kind {
        case .email:
            return .emails
        case .phoneNumber:
            return .phones
        case .creditCard:
            return .cards
        case .ipAddress:
            return .ipAddresses
        case .barcode:
            return .visualCodes
        case .face:
            return .faces
        case .apiKey, .url:
            return .secrets
        case .secret:
            return label == "High-entropy secret" ? .highEntropy : .secrets
        case .unknown:
            if label == "Account/customer ID" {
                return .customerAccount
            }
            return .custom
        }
    }
}
