import CoreGraphics
import Foundation

public struct SensitiveTextDetector: Sendable {
    private struct Rule: Sendable {
        let kind: DetectionKind
        let label: String
        let reason: String
        let policyPackID: RedactionPolicyPackID
        let detectorCategory: DetectorCategory
        let confidence: Double
        let regex: NSRegularExpression
        let matchGroup: Int
        let validator: (@Sendable (String, String, NSRange) -> Bool)?
        let suggestedAction: DetectionSuggestedAction
    }

    private let rules: [Rule]
    private let allowlist: Set<String>
    private let learnedSafeRules: [LearnedSafeRule]
    private let policyConfiguration: RedactionPolicyConfiguration
    private let detectorCategoryPreferences: DetectorCategoryPreferences

    public init(customConfiguration: CustomDetectionConfiguration = .empty) {
        rules = Self.defaultRules + Self.customRules(from: customConfiguration)
        allowlist = Set(customConfiguration.allowlist.map(Self.normalizedAllowlistValue))
        learnedSafeRules = customConfiguration.learnedSafeRules
        policyConfiguration = customConfiguration.policyConfiguration
        detectorCategoryPreferences = customConfiguration.detectorCategoryPreferences
    }

    public func detections(in observations: [TextObservation]) -> [Detection] {
        observations.flatMap { observation in
            let detections = rules.flatMap { rule in
                let policyDisposition = policyConfiguration.disposition(for: rule.policyPackID)
                    ?? RedactionPolicyDisposition(suggestedAction: rule.suggestedAction)
                let resolvedDisposition = detectorCategoryPreferences.resolvedDisposition(
                    for: rule.detectorCategory,
                    detectorLabel: rule.label,
                    defaultDisposition: policyDisposition
                )

                guard resolvedDisposition != .ignore else {
                    return [Detection]()
                }

                return matches(
                    rule.regex,
                    in: observation.text,
                    matchGroup: rule.matchGroup,
                    validator: rule.validator,
                    detectorLabel: rule.label
                ).map { match in
                    let resolved = observation.bounds(for: match.range)
                    let confidence = Self.detectionConfidence(
                        ruleConfidence: rule.confidence,
                        observationConfidence: observation.confidence,
                        boundsPrecision: resolved.precision
                    )
                    return Detection(
                        kind: rule.kind,
                        label: rule.label,
                        confidence: confidence,
                        normalizedBounds: resolved.bounds,
                        source: .deterministic,
                        reason: rule.reason,
                        matchedText: match.value,
                        matchedRange: TextRange(match.nsRange),
                        suggestedAction: Self.suggestedAction(
                            policyAction: resolvedDisposition.suggestedAction,
                            observationConfidence: observation.confidence
                        ),
                        boundsPrecision: resolved.precision
                    )
                }
            }
            return Self.resolveOverlaps(in: detections)
        }
    }

    private func matches(
        _ regex: NSRegularExpression,
        in text: String,
        matchGroup: Int,
        validator: (@Sendable (String, String, NSRange) -> Bool)?,
        detectorLabel: String
    ) -> [(value: String, range: Range<String.Index>, nsRange: NSRange)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > matchGroup else { return nil }
            let nsRange = match.range(at: matchGroup)
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { return nil }
            guard let swiftRange = Range(nsRange, in: text) else { return nil }
            let value = String(text[swiftRange])
            guard validator?(value, text, nsRange) ?? true else { return nil }
            guard !isAllowlisted(value, detectorLabel: detectorLabel) else { return nil }
            return (value, swiftRange, nsRange)
        }
    }

    private func isAllowlisted(_ value: String, detectorLabel: String?) -> Bool {
        allowlist.contains(Self.normalizedAllowlistValue(value))
            || learnedSafeRules.contains { $0.matches(value, detectorLabel: detectorLabel) }
    }

    private static func detectionConfidence(
        ruleConfidence: Double,
        observationConfidence: Double,
        boundsPrecision: DetectionBoundsPrecision
    ) -> Double {
        let confidence = min(ruleConfidence, observationConfidence)
        return boundsPrecision == .lineFallback ? min(confidence, 0.74) : confidence
    }

    private static func suggestedAction(
        policyAction: DetectionSuggestedAction,
        observationConfidence: Double
    ) -> DetectionSuggestedAction {
        if policyAction == .ignore {
            return .ignore
        }

        return observationConfidence < 0.8 ? .review : policyAction
    }

    private static let defaultRules: [Rule] = [
        makeRule(
            kind: .apiKey,
            label: "AWS key",
            reason: "AWS access key IDs should not be shared in screenshots.",
            policyPackID: .secrets,
            confidence: 0.98,
            pattern: #"\b(A3T[A-Z0-9]|AKIA|ASIA)[A-Z0-9]{16}\b"#
        ),
        makeRule(
            kind: .apiKey,
            label: "GitHub token",
            reason: "GitHub access tokens can grant repository or account access.",
            policyPackID: .secrets,
            confidence: 0.98,
            pattern: #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"#
        ),
        makeRule(
            kind: .apiKey,
            label: "Stripe secret key",
            reason: "Stripe secret keys can expose payment account access.",
            policyPackID: .secrets,
            confidence: 0.98,
            pattern: #"\bsk_(live|test)_[A-Za-z0-9]{16,}\b"#
        ),
        makeRule(
            kind: .secret,
            label: "Bearer token",
            reason: "Bearer tokens can authenticate API requests.",
            policyPackID: .secrets,
            confidence: 0.94,
            pattern: #"\bBearer\s+[A-Za-z0-9._~+/\-]+=*\b"#
        ),
        makeRule(
            kind: .secret,
            label: "JWT",
            reason: "JWTs can contain claims or credentials.",
            policyPackID: .secrets,
            confidence: 0.92,
            pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#
        ),
        makeRule(
            kind: .secret,
            label: "SSH public key",
            reason: "SSH authorized keys reveal account access configuration and should be reviewed before sharing.",
            policyPackID: .secrets,
            confidence: 0.9,
            pattern: #"\bssh-(?:rsa|ed25519|ecdsa-sha2-nistp(?:256|384|521))\s+(?:[A-Za-z0-9+/=]\s*){40,}(?:[^\S\r\n]+[^\s,;\]}]+)?"#,
            options: [.caseInsensitive],
            suggestedAction: .review
        ),
        makeRule(
            kind: .secret,
            label: "Environment secret",
            reason: "Environment variable secrets can expose credentials or tokens.",
            policyPackID: .secrets,
            confidence: 0.93,
            pattern: #"(?:^|[\s;])[A-Z_][A-Z0-9_-]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|CLIENT[_-]?SECRET|AUTH)[A-Z0-9_-]*\s*[:=]\s*['"]?([^\s'"]{6,})['"]?"#,
            options: [.caseInsensitive],
            matchGroup: 1,
            validator: { value, _, _ in
                !isPlaceholderSecret(value)
            }
        ),
        makeRule(
            kind: .url,
            label: "URL query token",
            reason: "Private URL parameters can grant access or reveal account data.",
            policyPackID: .secrets,
            confidence: 0.93,
            pattern: #"\bhttps?://[^\s<>"'?]+\?(?:[^\s<>"'&]+&)*(?:access[_-]?token|auth[_-]?token|api[_-]?key|apikey|client[_-]?secret|code|key|password|secret|session|sig|signature|token)=([^&\s<>"']{6,})[^\s<>"']*"#,
            options: [.caseInsensitive],
            matchGroup: 1,
            validator: { value, _, _ in
                !isPlaceholderSecret(value)
            }
        ),
        makeRule(
            kind: .apiKey,
            label: "Google API key",
            reason: "Google API keys can expose project or service access.",
            policyPackID: .secrets,
            confidence: 0.97,
            pattern: #"\bAIza[A-Za-z0-9_-]{35}\b"#
        ),
        makeRule(
            kind: .apiKey,
            label: "OpenAI API key",
            reason: "OpenAI API keys can expose account access and usage.",
            policyPackID: .secrets,
            confidence: 0.97,
            pattern: #"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"#
        ),
        makeRule(
            kind: .apiKey,
            label: "Slack token",
            reason: "Slack tokens can expose workspace or app access.",
            policyPackID: .secrets,
            confidence: 0.97,
            pattern: #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#
        ),
        makeRule(
            kind: .email,
            label: "Email",
            reason: "Email addresses can identify a person or account.",
            policyPackID: .pii,
            confidence: 0.9,
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            options: [.caseInsensitive]
        ),
        makeRule(
            kind: .ipAddress,
            label: "IP address",
            reason: "IP addresses can reveal infrastructure or location context.",
            policyPackID: .customerAccount,
            confidence: 0.86,
            pattern: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#,
            suggestedAction: .review
        ),
        makeRule(
            kind: .phoneNumber,
            label: "Phone number",
            reason: "Phone numbers can identify or contact a person.",
            policyPackID: .pii,
            confidence: 0.84,
            pattern: #"(?<![\w])(?:\+?1[\s.-]?)?(?:\([2-9]\d{2}\)|[2-9]\d{2})[\s.-]?[2-9]\d{2}[\s.-]?\d{4}(?:\s*(?:x|ext\.?)\s*\d{1,6})?(?![\w])"#,
            options: [.caseInsensitive],
            validator: { value, text, nsRange in
                isPlausiblePhoneNumber(value, in: text, nsRange: nsRange)
            }
        ),
        makeRule(
            kind: .creditCard,
            label: "Card number",
            reason: "Card numbers should be redacted before sharing.",
            policyPackID: .pii,
            confidence: 0.95,
            pattern: #"\b(?:\d{13,19}|\d{4}[ -]\d{4}[ -]\d{4}(?:[ -]\d{1,7})?|\d{4}[ -]\d{6}[ -]\d{5})\b"#,
            validator: { value, _, _ in
                passesLuhn(value)
            }
        ),
        makeRule(
            kind: .unknown,
            label: "Account/customer ID",
            reason: "Customer and account identifiers can reveal private business context.",
            policyPackID: .customerAccount,
            confidence: 0.72,
            pattern: #"(?<![A-Za-z0-9])(?:customer|account|acct|tenant|workspace)[_-][A-Za-z0-9][A-Za-z0-9_-]{6,}[A-Za-z0-9](?![A-Za-z0-9])"#,
            options: [.caseInsensitive],
            validator: { value, text, nsRange in
                isPlausibleCustomerAccountIdentifier(value, in: text, nsRange: nsRange)
            },
            suggestedAction: .review
        ),
        makeRule(
            kind: .secret,
            label: "High-entropy secret",
            reason: "Random-looking tokens can expose application or account access.",
            policyPackID: .secrets,
            confidence: 0.76,
            pattern: #"(?<![A-Za-z0-9])(?=[A-Za-z0-9_/\-+=]{28,})(?=[A-Za-z0-9_/\-+=]*[a-z])(?=[A-Za-z0-9_/\-+=]*[A-Z])(?=[A-Za-z0-9_/\-+=]*\d)[A-Za-z0-9_/\-+=]{28,}(?![A-Za-z0-9])"#,
            detectorCategory: .highEntropy,
            validator: { value, text, nsRange in
                isHighEntropySecret(value, in: text, nsRange: nsRange)
            },
            suggestedAction: .review
        ),
        makeRule(
            kind: .unknown,
            label: "Confidential label",
            reason: "Matched a visible confidentiality label. This is policy matching, not semantic classification.",
            policyPackID: .companyConfidential,
            confidence: 0.88,
            pattern: #"\b(?:CONFIDENTIAL|INTERNAL\s+ONLY|DO\s+NOT\s+SHARE|NDA|PROPRIETARY|RESTRICTED)\b"#,
            options: [.caseInsensitive],
            suggestedAction: .review
        )
    ]

    private static func customRules(from configuration: CustomDetectionConfiguration) -> [Rule] {
        let termRules = configuration.terms.map { term in
            makeRule(
                kind: .unknown,
                label: "Custom term",
                reason: "Matched a local custom term.",
                policyPackID: .custom,
                confidence: 0.96,
                pattern: NSRegularExpression.escapedPattern(for: term),
                options: [.caseInsensitive]
            )
        }

        let regexRules = configuration.regexes.compactMap { pattern in
            makeOptionalRule(
                kind: .unknown,
                label: "Custom pattern",
                reason: "Matched a local custom pattern.",
                policyPackID: .custom,
                confidence: 0.9,
                pattern: pattern
            )
        }

        return termRules + regexRules
    }

    private static func makeRule(
        kind: DetectionKind,
        label: String,
        reason: String,
        policyPackID: RedactionPolicyPackID,
        confidence: Double,
        pattern: String,
        options: NSRegularExpression.Options = [],
        matchGroup: Int = 0,
        detectorCategory: DetectorCategory? = nil,
        validator: (@Sendable (String, String, NSRange) -> Bool)? = nil,
        suggestedAction: DetectionSuggestedAction = .redact
    ) -> Rule {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("Invalid detector regex for \(label)")
        }
        return Rule(
            kind: kind,
            label: label,
            reason: reason,
            policyPackID: policyPackID,
            detectorCategory: detectorCategory ?? defaultDetectorCategory(kind: kind, label: label),
            confidence: confidence,
            regex: regex,
            matchGroup: matchGroup,
            validator: validator,
            suggestedAction: suggestedAction
        )
    }

    private static func makeOptionalRule(
        kind: DetectionKind,
        label: String,
        reason: String,
        policyPackID: RedactionPolicyPackID,
        confidence: Double,
        pattern: String,
        options: NSRegularExpression.Options = [],
        matchGroup: Int = 0,
        detectorCategory: DetectorCategory? = nil,
        validator: (@Sendable (String, String, NSRange) -> Bool)? = nil,
        suggestedAction: DetectionSuggestedAction = .redact
    ) -> Rule? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        return Rule(
            kind: kind,
            label: label,
            reason: reason,
            policyPackID: policyPackID,
            detectorCategory: detectorCategory ?? defaultDetectorCategory(kind: kind, label: label),
            confidence: confidence,
            regex: regex,
            matchGroup: matchGroup,
            validator: validator,
            suggestedAction: suggestedAction
        )
    }

    private static func defaultDetectorCategory(kind: DetectionKind, label: String) -> DetectorCategory {
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

    private static func resolveOverlaps(in detections: [Detection]) -> [Detection] {
        detections
            .sorted(by: detectionPrecedence)
            .reduce(into: [Detection]()) { accepted, candidate in
                let duplicatesExisting = accepted.contains { existing in
                    guard let candidateRange = candidate.matchedRange,
                          let existingRange = existing.matchedRange
                    else { return false }

                    let existingEnd = existingRange.location + existingRange.length
                    let candidateEnd = candidateRange.location + candidateRange.length
                    if candidateRange.location >= existingRange.location && candidateEnd <= existingEnd {
                        return true
                    }
                    // The entropy rule also matches "key=value". The structured rule already
                    // masks the entire value, and the parameter name alone is not a secret.
                    guard candidate.label == "High-entropy secret",
                          existing.label == "URL query token" || existing.label == "Environment secret",
                          candidateEnd == existingEnd, candidateRange.location < existingRange.location,
                          let value = existing.matchedText, let assignment = candidate.matchedText
                    else { return false }
                    return assignment.hasSuffix("=" + value)
                }

                if !duplicatesExisting {
                    accepted.append(candidate)
                }
            }
            .sorted(by: readingOrder)
    }

    private static func detectionPrecedence(_ lhs: Detection, _ rhs: Detection) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        if lhs.suggestedAction != rhs.suggestedAction {
            return actionRank(lhs.suggestedAction) > actionRank(rhs.suggestedAction)
        }

        let lhsLength = lhs.matchedRange?.length ?? Int.max
        let rhsLength = rhs.matchedRange?.length ?? Int.max
        if lhsLength != rhsLength {
            return lhsLength > rhsLength
        }

        return lhs.label < rhs.label
    }

    private static func readingOrder(_ lhs: Detection, _ rhs: Detection) -> Bool {
        let lhsLocation = lhs.matchedRange?.location ?? Int.max
        let rhsLocation = rhs.matchedRange?.location ?? Int.max
        if lhsLocation != rhsLocation {
            return lhsLocation < rhsLocation
        }

        return lhs.label < rhs.label
    }

    private static func actionRank(_ action: DetectionSuggestedAction) -> Int {
        switch action {
        case .redact: 3
        case .review: 2
        case .ignore: 1
        }
    }

    private static func normalizedAllowlistValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func passesLuhn(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }

        var sum = 0
        var shouldDouble = false
        for digit in digits.reversed() {
            var value = digit
            if shouldDouble {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
            shouldDouble.toggle()
        }

        return sum % 10 == 0
    }

    private static func isPlausiblePhoneNumber(_ value: String, in text: String, nsRange: NSRange) -> Bool {
        let baseValue = phoneNumberBaseValue(value)
        let digits = baseValue.compactMap(\.wholeNumberValue)
        guard digits.count == 10 || (digits.count == 11 && digits.first == 1) else { return false }

        let hasPlus = baseValue.contains("+")
        let hasParentheses = baseValue.contains("(") || baseValue.contains(")")
        let hasHyphen = baseValue.contains("-")
        let hasDot = baseValue.contains(".")
        let hasWhitespace = baseValue.contains(where: \.isWhitespace)
        guard hasPlus || hasParentheses || hasHyphen || hasDot || hasWhitespace else { return false }

        if hasDot {
            guard isWellGroupedDottedPhone(baseValue) else { return false }
        }

        let separatorCount = baseValue.reduce(into: 0) { count, character in
            if character == "-" || character == "." || character.isWhitespace {
                count += 1
            }
        }

        if !hasPlus, !hasParentheses, separatorCount < 2 {
            return false
        }

        if hasWhitespace, !hasPlus, !hasParentheses, !hasHyphen, !hasDot {
            guard hasNearbyPhoneContext(in: text, around: nsRange) else { return false }
        }

        return Set(digits).count >= 4
    }

    private static func phoneNumberBaseValue(_ value: String) -> String {
        let nsValue = value as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        let extensionPattern = #"(?i)\s*(?:x|ext\.?)\s*\d{1,6}\s*$"#
        guard let regex = try? NSRegularExpression(pattern: extensionPattern) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return regex
            .stringByReplacingMatches(in: value, range: fullRange, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isWellGroupedDottedPhone(_ value: String) -> Bool {
        let pattern = #"^\s*(?:\+?1[ .-]?)?(?:[2-9]\d{2}\.[2-9]\d{2}\.\d{4})\s*$"#
        return (try? NSRegularExpression(pattern: pattern))
            .map { regex in
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                return regex.firstMatch(in: value, range: range) != nil
            } ?? false
    }

    private static func hasNearbyPhoneContext(in text: String, around nsRange: NSRange) -> Bool {
        let nsText = text as NSString
        let contextStart = max(0, nsRange.location - 32)
        let contextEnd = min(nsText.length, nsRange.location + nsRange.length + 32)
        guard contextEnd > contextStart else { return false }

        let context = nsText
            .substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
            .lowercased()
        let pattern = #"\b(?:call|cell|contact|fax|mobile|phone|sms|support|tel|telephone)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(context.startIndex..<context.endIndex, in: context)
        return regex.firstMatch(in: context, range: range) != nil
    }

    private static func isPlaceholderSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        let lowercased = trimmed.lowercased()

        let placeholders: Set<String> = [
            "changeme",
            "example",
            "fake",
            "placeholder",
            "redacted",
            "sample",
            "secret",
            "test",
            "todo",
            "your_key_here",
            "your-token-here"
        ]

        return placeholders.contains(lowercased)
            || lowercased.allSatisfy { $0 == "x" || $0 == "*" || $0 == "-" }
    }

    private static func isHighEntropySecret(_ value: String, in text: String, nsRange: NSRange) -> Bool {
        guard value.count >= 28 else { return false }

        let hasSecretContext = hasStrongSecretContext(in: text, around: nsRange)
        if !hasSecretContext {
            guard !isKnownLowRiskIdentifier(value) else { return false }
            guard !isLikelyFilesystemOrLogPath(value) else { return false }
            guard !isLikelyDeploymentTagOrBranchName(value) else { return false }
            guard !isLikelyProductOrEnvironmentLabel(value) else { return false }
            guard !isLikelyCodeOrMetricIdentifier(value) else { return false }
        }

        return shannonEntropy(value) >= (hasSecretContext ? 3.8 : 4.25)
    }

    private static func isPlausibleCustomerAccountIdentifier(_ value: String, in text: String, nsRange: NSRange) -> Bool {
        guard !value.compactMap(\.wholeNumberValue).isEmpty,
              !isPlaceholderSecret(value),
              !isLikelyInfrastructureIdentifier(value)
        else {
            return false
        }

        let lowercased = value.lowercased()
        if lowercased.hasPrefix("customer_")
            || lowercased.hasPrefix("customer-")
            || lowercased.hasPrefix("account_")
            || lowercased.hasPrefix("account-")
            || lowercased.hasPrefix("acct_")
            || lowercased.hasPrefix("acct-") {
            return true
        }

        return hasCustomerAccountContext(in: text, around: nsRange)
    }

    private static func hasCustomerAccountContext(in text: String, around nsRange: NSRange) -> Bool {
        guard let matchRange = Range(nsRange, in: text) else { return false }

        let lineStart = text[..<matchRange.lowerBound].lastIndex(of: "\n").map {
            text.index(after: $0)
        } ?? text.startIndex
        let lineEnd = text[matchRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let contextStart = text.index(matchRange.lowerBound, offsetBy: -48, limitedBy: lineStart) ?? lineStart
        let contextEnd = text.index(matchRange.upperBound, offsetBy: 48, limitedBy: lineEnd) ?? lineEnd
        let context = text[contextStart..<contextEnd].lowercased()

        let accountTerms = [
            "account id",
            "account:",
            "account=",
            "acct",
            "customer id",
            "customer:",
            "customer=",
            "tenant id",
            "workspace id"
        ]

        return accountTerms.contains { context.contains($0) }
    }

    private static func isLikelyInfrastructureIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let infrastructureTerms = [
            "aggregate",
            "analytics",
            "collector",
            "controller",
            "cron",
            "cronjob",
            "db2",
            "deployment",
            "engine",
            "fetcher",
            "health",
            "keeper",
            "kube",
            "kubernetes",
            "load",
            "metrics",
            "mongo",
            "namespace",
            "partition",
            "pod",
            "postgres",
            "pulse",
            "scheduler",
            "service",
            "status",
            "sync",
            "table",
            "tables",
            "worker"
        ]

        let separatorCount = value.filter { $0 == "-" || $0 == "_" }.count
        return separatorCount >= 2 && infrastructureTerms.contains { lowercased.contains($0) }
    }

    private static func isKnownLowRiskIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("customer_")
            || lowercased.hasPrefix("account_")
            || lowercased.hasPrefix("invoice_")
            || lowercased.hasPrefix("order_") {
            return true
        }

        let uuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        return value.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func hasStrongSecretContext(in text: String, around nsRange: NSRange) -> Bool {
        guard let matchRange = Range(nsRange, in: text) else { return false }

        let lineStart = text[..<matchRange.lowerBound].lastIndex(of: "\n").map {
            text.index(after: $0)
        } ?? text.startIndex
        let lineEnd = text[matchRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let contextStart = text.index(matchRange.lowerBound, offsetBy: -80, limitedBy: lineStart) ?? lineStart
        let contextEnd = text.index(matchRange.upperBound, offsetBy: 24, limitedBy: lineEnd) ?? lineEnd
        let context = text[contextStart..<contextEnd].lowercased()

        let strongTerms = [
            "access_key",
            "access-key",
            "api_key",
            "api-key",
            "apikey",
            "authorization",
            "bearer",
            "client_secret",
            "credential",
            "password",
            "private_key",
            "secret",
            "token"
        ]

        return strongTerms.contains { context.contains($0) }
    }

    private static func isLikelyFilesystemOrLogPath(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("/")
            || lowercased.hasPrefix("~/")
            || lowercased.contains("\\")
            || lowercased.contains("/var/")
            || lowercased.contains("/tmp/")
            || lowercased.contains("/mnt/")
            || lowercased.contains("/users/")
            || lowercased.contains("/node")
            || lowercased.contains("/log")
            || lowercased.contains("logstream")
            || lowercased.contains("sqlog")
            || lowercased.contains("database") {
            return true
        }

        let slashCount = value.filter { $0 == "/" }.count
        return slashCount >= 2
    }

    private static func isLikelyDeploymentTagOrBranchName(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let deploymentTerms = [
            "build",
            "deploy",
            "deployment",
            "dev",
            "main",
            "master",
            "prod",
            "stage",
            "staging",
            "tag",
            "test"
        ]

        if deploymentTerms.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let hyphenCount = value.filter { $0 == "-" }.count
        let dotCount = value.filter { $0 == "." }.count
        let digitCount = value.compactMap(\.wholeNumberValue).count
        return hyphenCount >= 4 && digitCount >= 6 || dotCount >= 3 && digitCount >= 6
    }

    private static func isLikelyProductOrEnvironmentLabel(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let safeTerms = [
            "catalog",
            "cache",
            "config",
            "dashboard",
            "database",
            "event",
            "guardian",
            "insight",
            "server",
            "service",
            "stream",
            "threshold"
        ]

        guard safeTerms.contains(where: { lowercased.contains($0) }) else {
            return false
        }

        let separatorCount = value.filter { $0 == "-" || $0 == "_" || $0 == "." }.count
        return separatorCount >= 2
    }

    private static func isLikelyCodeOrMetricIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let hasMetricOrCodeTerm = [
            "consumer",
            "group",
            "lag",
            "maxoffset",
            "metric",
            "offset",
            "processor",
            "risk"
        ].contains { lowercased.contains($0) }

        guard hasMetricOrCodeTerm else { return false }

        let separatorCount = value.filter { $0 == "_" || $0 == "-" || $0 == "." }.count
        let letterCount = value.filter { $0.isLetter }.count
        let digitCount = value.compactMap(\.wholeNumberValue).count
        return separatorCount >= 2 && letterCount > digitCount
    }

    private static func shannonEntropy(_ value: String) -> Double {
        let counts = value.reduce(into: [Character: Double]()) { result, character in
            result[character, default: 0] += 1
        }
        let length = Double(value.count)

        return counts.values.reduce(0) { entropy, count in
            let probability = count / length
            return entropy - probability * log2(probability)
        }
    }
}
