import Foundation

public enum RedaktrBuildTrustKind: String, Codable, Equatable, Sendable {
    case notarizedDeveloperID
    case developmentSigned
    case adHocOrUnsigned
    case gatekeeperRejected
    case unknownSigned
}

public struct RedaktrBuildTrustInput: Equatable, Sendable {
    public var isDebugBuild: Bool
    public var teamIdentifier: String?
    public var signingAuthority: String?
    public var gatekeeperAccepted: Bool?

    public init(
        isDebugBuild: Bool,
        teamIdentifier: String?,
        signingAuthority: String?,
        gatekeeperAccepted: Bool?
    ) {
        self.isDebugBuild = isDebugBuild
        self.teamIdentifier = teamIdentifier
        self.signingAuthority = signingAuthority
        self.gatekeeperAccepted = gatekeeperAccepted
    }
}

public struct RedaktrBuildTrustAssessment: Equatable, Sendable {
    public var kind: RedaktrBuildTrustKind
    public var isTrustedForAmbientDistribution: Bool
    public var userFacingWarning: String?

    public init(
        kind: RedaktrBuildTrustKind,
        isTrustedForAmbientDistribution: Bool,
        userFacingWarning: String?
    ) {
        self.kind = kind
        self.isTrustedForAmbientDistribution = isTrustedForAmbientDistribution
        self.userFacingWarning = userFacingWarning
    }
}

public enum RedaktrBuildTrustEvaluator {
    public static func assess(_ input: RedaktrBuildTrustInput) -> RedaktrBuildTrustAssessment {
        if input.gatekeeperAccepted == false {
            return RedaktrBuildTrustAssessment(
                kind: .gatekeeperRejected,
                isTrustedForAmbientDistribution: false,
                userFacingWarning: "This Redaktr build is not accepted by Gatekeeper. Verify notifications on the signed distribution candidate."
            )
        }

        let authority = input.signingAuthority?.lowercased() ?? ""
        let hasTeamIdentifier = !(input.teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasTeamIdentifier || authority.contains("adhoc") || authority.contains("ad hoc") {
            return RedaktrBuildTrustAssessment(
                kind: .adHocOrUnsigned,
                isTrustedForAmbientDistribution: false,
                userFacingWarning: "This Redaktr build is unsigned or ad-hoc signed. Verify notifications on the signed distribution candidate."
            )
        }

        if input.isDebugBuild || authority.contains("apple development") {
            return RedaktrBuildTrustAssessment(
                kind: .developmentSigned,
                isTrustedForAmbientDistribution: false,
                userFacingWarning: "Development builds can behave differently with macOS notifications and Gatekeeper. Verify both on the distribution candidate."
            )
        }

        if authority.contains("developer id application") && input.gatekeeperAccepted == true {
            return RedaktrBuildTrustAssessment(
                kind: .notarizedDeveloperID,
                isTrustedForAmbientDistribution: true,
                userFacingWarning: nil
            )
        }

        return RedaktrBuildTrustAssessment(
            kind: .unknownSigned,
            isTrustedForAmbientDistribution: false,
            userFacingWarning: "This build has no verified Gatekeeper assessment. Verify notifications on the signed distribution candidate."
        )
    }
}
