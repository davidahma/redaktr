import Foundation

public enum PolicySource: String, Codable, CaseIterable, Sendable {
    case local
    case imported
    case managed
}

public enum PolicyField: String, Codable, CaseIterable, Sendable {
    case policyPreset
    case customTerms
    case customRegexes
    case allowlist
}

public struct PolicyLock: Codable, Equatable, Sendable {
    public var lockedFields: Set<PolicyField>

    public init(lockedFields: Set<PolicyField> = []) {
        self.lockedFields = lockedFields
    }

    public func isLocked(_ field: PolicyField) -> Bool {
        lockedFields.contains(field)
    }
}

public struct RedaktrPortableSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var appVersion: String?
    public var source: PolicySource
    public var lock: PolicyLock
    public var customConfiguration: CustomDetectionConfiguration
    public var policyPresetID: RedactionPolicyPresetID?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        appVersion: String? = nil,
        source: PolicySource = .local,
        lock: PolicyLock = PolicyLock(),
        customConfiguration: CustomDetectionConfiguration,
        policyPresetID: RedactionPolicyPresetID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.source = source
        self.lock = lock
        self.customConfiguration = customConfiguration
        self.policyPresetID = policyPresetID
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appVersion
        case source
        case lock
        case customConfiguration
        case policyPresetID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        source = try container.decodeIfPresent(PolicySource.self, forKey: .source) ?? .local
        lock = try container.decodeIfPresent(PolicyLock.self, forKey: .lock) ?? PolicyLock()
        customConfiguration = try container.decode(CustomDetectionConfiguration.self, forKey: .customConfiguration)
        if let rawPresetID = try container.decodeIfPresent(String.self, forKey: .policyPresetID) {
            policyPresetID = RedactionPolicyPresetID.normalized(rawValue: rawPresetID)
        } else {
            policyPresetID = nil
        }
    }
}
