import Foundation

public struct CustomDetectionConfiguration: Codable, Equatable, Sendable {
    public static let empty = CustomDetectionConfiguration()

    public var terms: [String]
    public var regexes: [String]
    public var allowlist: [String]
    public var policyConfiguration: RedactionPolicyConfiguration
    public var detectorCategoryPreferences: DetectorCategoryPreferences
    public var learnedSafeRules: [LearnedSafeRule]

    public init(
        terms: [String] = [],
        regexes: [String] = [],
        allowlist: [String] = [],
        policyConfiguration: RedactionPolicyConfiguration = .currentDefaults,
        detectorCategoryPreferences: DetectorCategoryPreferences = .allEnabled,
        learnedSafeRules: [LearnedSafeRule] = []
    ) {
        self.terms = Self.normalizedEntries(terms)
        self.regexes = Self.normalizedEntries(regexes, caseSensitive: true)
        self.allowlist = Self.normalizedEntries(allowlist)
        self.policyConfiguration = policyConfiguration
        self.detectorCategoryPreferences = detectorCategoryPreferences
        self.learnedSafeRules = Self.normalizedLearnedSafeRules(learnedSafeRules)
    }

    enum CodingKeys: String, CodingKey {
        case terms
        case regexes
        case allowlist
        case policyConfiguration
        case detectorCategoryPreferences
        case learnedSafeRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            terms: try container.decodeIfPresent([String].self, forKey: .terms) ?? [],
            regexes: try container.decodeIfPresent([String].self, forKey: .regexes) ?? [],
            allowlist: try container.decodeIfPresent([String].self, forKey: .allowlist) ?? [],
            policyConfiguration: try container.decodeIfPresent(
                RedactionPolicyConfiguration.self,
                forKey: .policyConfiguration
            ) ?? .currentDefaults,
            detectorCategoryPreferences: try container.decodeIfPresent(
                DetectorCategoryPreferences.self,
                forKey: .detectorCategoryPreferences
            ) ?? .allEnabled,
            learnedSafeRules: try container.decodeIfPresent(
                [LearnedSafeRule].self,
                forKey: .learnedSafeRules
            ) ?? []
        )
    }

    public var invalidRegexPatterns: [String] {
        regexes.filter { pattern in
            (try? NSRegularExpression(pattern: pattern)) == nil
        }
    }

    private static func normalizedEntries(_ entries: [String], caseSensitive: Bool = false) -> [String] {
        var seen = Set<String>()
        var normalized = [String]()

        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = caseSensitive ? trimmed : trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            normalized.append(trimmed)
        }

        return normalized
    }

    private static func normalizedLearnedSafeRules(_ rules: [LearnedSafeRule]) -> [LearnedSafeRule] {
        var seen = Set<String>()
        var normalized = [LearnedSafeRule]()

        for rule in rules {
            guard !rule.value.isEmpty else { continue }
            let key = [
                rule.matchKind.rawValue,
                LearnedSafeRule.normalized(rule.value),
                rule.detectorLabel ?? "",
                String(describing: rule.scope)
            ].joined(separator: "\u{1F}")
            guard seen.insert(key).inserted else { continue }
            normalized.append(rule)
        }

        return normalized
    }
}
