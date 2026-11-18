import CoreGraphics
import RedaktrCore
import XCTest

final class SafeShareHistoryTests: XCTestCase {
    func testHistoryRecordSerializesOnlySafeMetadata() throws {
        let plan = RedactionPlan(textDetections: [
            Detection(
                kind: .apiKey,
                label: "AWS key",
                confidence: 0.99,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1),
                source: .deterministic,
                reason: "AWS access key IDs should not be shared in screenshots.",
                matchedText: "AKIAIOSFODNN7EXAMPLE",
                suggestedAction: .redact,
                boundsPrecision: .tight
            )
        ])
        let record = SafeShareHistoryRecord(
            sourceType: .capture,
            action: .scan,
            plan: plan,
            policySummary: "Imported policy: AI sharing",
            outputPath: "/Users/david/Desktop/clean.png"
        )

        let data = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("capture"))
        XCTAssertTrue(json.contains("scan"))
        XCTAssertTrue(json.contains("Imported policy"))
        XCTAssertTrue(json.contains("clean.png"))
        XCTAssertFalse(json.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("matchedText"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("imageData"))
    }

    func testHistoryStoreKeepsNewestRecordsWithinLimit() {
        var store = SafeShareHistoryStore()

        for index in 0..<5 {
            store.append(
                SafeShareHistoryRecord(
                    occurredAt: Date(timeIntervalSince1970: Double(index)),
                    sourceType: .fileImport,
                    action: .scan,
                    totalFindings: index,
                    includedFindings: index,
                    reviewFindings: 0,
                    offFindings: 0
                ),
                limit: 3
            )
        }

        XCTAssertEqual(store.records.count, 3)
        XCTAssertEqual(store.records.map(\.totalFindings), [4, 3, 2])
    }

    func testPortableSettingsDoNotIncludeHistory() throws {
        let settings = RedaktrPortableSettings(
            appVersion: "0.1.0",
            source: .imported,
            lock: PolicyLock(lockedFields: [.policyPreset, .customTerms]),
            customConfiguration: CustomDetectionConfiguration(
                terms: ["Project Monarch"],
                regexes: ["ACCT-[0-9]+"],
                allowlist: ["example.com"],
                policyConfiguration: RedactionPolicyConfiguration(preset: .safeSharing)
            ),
            policyPresetID: .safeSharing
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(RedaktrPortableSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(json.contains("Project Monarch"))
        XCTAssertTrue(json.contains("safeSharing"))
        XCTAssertTrue(json.contains("imported"))
        XCTAssertTrue(json.contains("policyPreset"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("history"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("sourceImage"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("license"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("billing"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("matchedText"))
    }
}
