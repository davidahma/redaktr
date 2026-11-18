import CoreGraphics
import XCTest
@testable import RedaktrCore

final class RedactionPolicyTests: XCTestCase {
    func testPolicyPackDefinitionsCoverRequiredCategories() {
        let packsByID = Dictionary(uniqueKeysWithValues: RedactionPolicyCatalog.packs.map { ($0.id, $0) })

        XCTAssertEqual(Set(packsByID.keys), Set(RedactionPolicyPackID.allCases))
        XCTAssertEqual(packsByID[.pii]?.defaultDisposition, .autoRedact)
        XCTAssertEqual(packsByID[.secrets]?.defaultDisposition, .autoRedact)
        XCTAssertEqual(packsByID[.companyConfidential]?.defaultDisposition, .needsReview)
        XCTAssertEqual(packsByID[.customerAccount]?.defaultDisposition, .needsReview)
        XCTAssertEqual(packsByID[.custom]?.defaultDisposition, .autoRedact)

        XCTAssertTrue(packsByID[.pii]?.detectorLabels.contains("Email") == true)
        XCTAssertTrue(packsByID[.secrets]?.detectorLabels.contains("GitHub token") == true)
        XCTAssertTrue(packsByID[.companyConfidential]?.detectorLabels.contains("Confidential label") == true)
        XCTAssertTrue(packsByID[.customerAccount]?.detectorLabels.contains("Account/customer ID") == true)
        XCTAssertTrue(packsByID[.custom]?.detectorLabels.contains("Custom term") == true)
    }

    func testPresetDefinitionsCoverPracticalShareModes() {
        let presetsByID = Dictionary(uniqueKeysWithValues: RedactionPolicyCatalog.presets.map { ($0.id, $0) })

        XCTAssertEqual(Set(presetsByID.keys), Set(RedactionPolicyPresetID.allCases))
        XCTAssertEqual(presetsByID[.safeSharing]?.policyDispositions[.secrets], .autoRedact)
        XCTAssertEqual(presetsByID[.developerDevOps]?.policyDispositions[.customerAccount], .needsReview)
        XCTAssertEqual(presetsByID[.supportCustomerData]?.policyDispositions[.pii], .needsReview)
        XCTAssertEqual(presetsByID[.finance]?.policyDispositions[.pii], .autoRedact)
        XCTAssertEqual(presetsByID[.healthcareRegulated]?.policyDispositions[.pii], .autoRedact)
        XCTAssertEqual(presetsByID[.companyConfidential]?.policyDispositions[.companyConfidential], .needsReview)
        XCTAssertEqual(presetsByID[.custom]?.policyDispositions[.secrets], .autoRedact)
    }

    func testLegacyPresetIDsNormalizeToCurrentWorkflowPresets() {
        XCTAssertEqual(RedactionPolicyPresetID.normalized(rawValue: "aiSharing"), .safeSharing)
        XCTAssertEqual(RedactionPolicyPresetID.normalized(rawValue: "publicDocs"), .safeSharing)
        XCTAssertEqual(RedactionPolicyPresetID.normalized(rawValue: "supportTicket"), .supportCustomerData)
        XCTAssertEqual(RedactionPolicyPresetID.normalized(rawValue: "internalTeammateSharing"), .custom)
    }

    func testPolicyPresetOverridesSuggestedActions() throws {
        let configuration = CustomDetectionConfiguration(
            policyConfiguration: RedactionPolicyConfiguration(preset: .custom)
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Email sam@example.com and key AKIAIOSFODNN7EXAMPLE.")
        ])

        let email = try XCTUnwrap(detections.first { $0.label == "Email" })
        let awsKey = try XCTUnwrap(detections.first { $0.label == "AWS key" })

        XCTAssertEqual(email.suggestedAction, .review)
        XCTAssertEqual(awsKey.suggestedAction, .redact)
    }

    func testPolicyCanIgnorePackAndSuppressNewFindings() throws {
        let configuration = CustomDetectionConfiguration(
            policyConfiguration: RedactionPolicyConfiguration(dispositions: [.pii: .ignore])
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Email sam@example.com before sharing.")
        ])

        XCTAssertFalse(detections.contains { $0.label == "Email" })
    }

    func testSafeSharingPresetReviewsCustomerAndRedactsCustomPolicyMatches() throws {
        let configuration = CustomDetectionConfiguration(
            terms: ["Project Monarch"],
            policyConfiguration: RedactionPolicyConfiguration(preset: .safeSharing)
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Customer customer_01HZYXWVUTSRQPONMLKJIHGFED maps to Project Monarch.")
        ])

        let customer = try XCTUnwrap(detections.first { $0.label == "Account/customer ID" })
        let customTerm = try XCTUnwrap(detections.first { $0.label == "Custom term" })

        XCTAssertEqual(customer.suggestedAction, .review)
        XCTAssertEqual(customTerm.suggestedAction, .redact)
    }

    func testDetectorTaxonomyGroupsCurrentAndFutureDetectorFamilies() {
        let entriesByLabel = Dictionary(uniqueKeysWithValues: DetectorCatalog.entries.map { ($0.label, $0) })

        XCTAssertEqual(entriesByLabel["AWS key"]?.taxonomyGroup, .secrets)
        XCTAssertEqual(entriesByLabel["Email"]?.taxonomyGroup, .personalData)
        XCTAssertEqual(entriesByLabel["Card number"]?.taxonomyGroup, .financialData)
        XCTAssertEqual(entriesByLabel["Government ID"]?.taxonomyGroup, .governmentIDs)
        XCTAssertEqual(entriesByLabel["Confidential label"]?.taxonomyGroup, .companyConfidential)
        XCTAssertEqual(entriesByLabel["Face"]?.taxonomyGroup, .visualContent)
        XCTAssertEqual(entriesByLabel["Custom term"]?.taxonomyGroup, .customPolicy)
        XCTAssertTrue(entriesByLabel["Kubeconfig/service-account token"]?.implemented == false)
        XCTAssertEqual(entriesByLabel["Generic domain"]?.defaultDisposition, .ignore)
        XCTAssertEqual(entriesByLabel["Person name"]?.defaultDisposition, .ignore)
        XCTAssertEqual(entriesByLabel["Date"]?.defaultDisposition, .ignore)
        XCTAssertEqual(entriesByLabel["Location"]?.defaultDisposition, .ignore)
        XCTAssertEqual(entriesByLabel["Broad numeric identifier"]?.defaultDisposition, .ignore)
        XCTAssertEqual(entriesByLabel["Meeting link"]?.defaultDisposition, .needsReview)
    }

    func testDetectorCategoryDispositionOverridesPresetAndSuppressesOffFindings() throws {
        var preferences = DetectorCategoryPreferences.allEnabled
        preferences.setDisposition(.needsReview, for: .emails)
        preferences.setDisposition(.ignore, for: .cards)
        let configuration = CustomDetectionConfiguration(
            policyConfiguration: RedactionPolicyConfiguration(preset: .safeSharing),
            detectorCategoryPreferences: preferences
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Email sam@example.com card 4242 4242 4242 4242 key AKIAIOSFODNN7EXAMPLE")
        ])

        let email = try XCTUnwrap(detections.first { $0.label == "Email" })
        XCTAssertEqual(email.suggestedAction, .review)
        XCTAssertFalse(detections.contains { $0.label == "Card number" })
        XCTAssertEqual(try XCTUnwrap(detections.first { $0.label == "AWS key" }).suggestedAction, .redact)
    }

    func testIndividualDetectorDispositionWinsOverCategoryDisposition() throws {
        var preferences = DetectorCategoryPreferences.allEnabled
        preferences.setDisposition(.autoRedact, for: .highEntropy)
        preferences.setDisposition(.needsReview, forDetectorLabel: "High-entropy secret")
        let configuration = CustomDetectionConfiguration(detectorCategoryPreferences: preferences)
        let token = "aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK"
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Generated token \(token)")
        ])

        let finding = try XCTUnwrap(detections.first { $0.label == "High-entropy secret" })
        XCTAssertEqual(finding.suggestedAction, .review)
    }

    func testLearnedSafeRulesSuppressExactRepeatValuesWithoutCloudTraining() {
        let configuration = CustomDetectionConfiguration(
            learnedSafeRules: [
                LearnedSafeRule(value: "staging-tenant-fetcher-db2-create-partitions", detectorLabel: "Account/customer ID")
            ]
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            textObservation("Customer staging-tenant-fetcher-db2-create-partitions")
        ])

        XCTAssertFalse(detections.contains { $0.label == "Account/customer ID" })
    }

    func testHighValueDetectorBacklogRequiresFixturesBeforeDefaultPromotion() {
        let labels = Set(DetectorBacklog.highValueItems.map(\.label))

        XCTAssertTrue(labels.contains("Session cookies"))
        XCTAssertTrue(labels.contains("Kubeconfig/service-account tokens"))
        XCTAssertTrue(labels.contains("Terraform state/vars secrets"))
        XCTAssertTrue(labels.contains("Person names"))
        XCTAssertTrue(labels.contains("Dates"))
        XCTAssertTrue(labels.contains("Locations"))
        XCTAssertTrue(labels.contains("Broad numeric identifiers"))
        XCTAssertTrue(DetectorBacklog.highValueItems.allSatisfy(\.requiresFixturesBeforeDefault))
        XCTAssertTrue(
            DetectorBacklog.highValueItems
                .filter {
                    [
                        "Meeting links",
                        "Generic domains",
                        "Person names",
                        "Dates",
                        "Locations",
                        "Broad numeric identifiers"
                    ].contains($0.label)
                }
                .allSatisfy { $0.defaultDisposition != .autoRedact }
        )
    }

    func testGenericNamesDatesLocationsDomainsAndLooseNumbersDoNotBecomeDefaultFindings() {
        let detections = SensitiveTextDetector().detections(in: [
            textObservation("Gilbert meets David in Toronto on March 2. example.com has 1234567 rows.")
        ])

        XCTAssertFalse(detections.contains { $0.label == "Generic domain" })
        XCTAssertFalse(detections.contains { $0.label == "Person name" })
        XCTAssertFalse(detections.contains { $0.label == "Date" })
        XCTAssertFalse(detections.contains { $0.label == "Location" })
        XCTAssertFalse(detections.contains { $0.label == "Broad numeric identifier" })
    }

    func testCompanyConfidentialVisibleLabelsAreReviewOnlyAndHonest() throws {
        let detections = SensitiveTextDetector().detections(in: [
            textObservation("CONFIDENTIAL - Internal Only roadmap.")
        ])

        let confidential = try XCTUnwrap(detections.first { $0.label == "Confidential label" })
        XCTAssertEqual(confidential.suggestedAction, .review)
        XCTAssertTrue(confidential.reason.localizedCaseInsensitiveContains("visible"))
        XCTAssertTrue(confidential.reason.localizedCaseInsensitiveContains("not semantic"))
    }

    func testPolicyActionExplanationMapsCommonStates() throws {
        let autoEntry = RedactionPlanEntry(
            detection: Detection(
                kind: .email,
                label: "Email",
                confidence: 0.98,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1),
                source: .deterministic,
                reason: "Email addresses can identify a person or account.",
                suggestedAction: .redact,
                boundsPrecision: .tight
            ),
            isActive: true
        )
        let reviewEntry = RedactionPlanEntry(
            detection: Detection(
                kind: .unknown,
                label: "Confidential label",
                confidence: 0.95,
                normalizedBounds: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.1),
                source: .deterministic,
                reason: "Matched a visible confidentiality label.",
                suggestedAction: .review,
                boundsPrecision: .tight
            ),
            isActive: true
        )
        let ignoredEntry = RedactionPlanEntry(
            detection: Detection(
                kind: .email,
                label: "Email",
                confidence: 0.98,
                normalizedBounds: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.1),
                source: .deterministic,
                reason: "Email addresses can identify a person or account.",
                suggestedAction: .ignore,
                boundsPrecision: .tight
            ),
            isActive: false
        )
        let turnedOffEntry = RedactionPlanEntry(detection: autoEntry.detection, isActive: false)

        XCTAssertEqual(PolicyActionExplanation(entry: autoEntry).label, "Auto-redacted")
        XCTAssertEqual(PolicyActionExplanation(entry: reviewEntry).label, "Needs review")
        XCTAssertEqual(PolicyActionExplanation(entry: ignoredEntry).label, "Off by policy")
        XCTAssertEqual(PolicyActionExplanation(entry: turnedOffEntry).label, "Turned off")
        XCTAssertTrue(PolicyActionExplanation(entry: autoEntry).detail.contains("Email"))
    }

    private func textObservation(_ text: String) -> TextObservation {
        TextObservation(
            text: text,
            normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
        )
    }
}
