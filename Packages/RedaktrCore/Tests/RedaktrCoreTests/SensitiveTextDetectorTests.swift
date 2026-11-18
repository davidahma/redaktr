import CoreGraphics
import RedaktrCore
import XCTest

final class SensitiveTextDetectorTests: XCTestCase {
    func testDetectsEmailAndStripeKey() {
        let observations = [
            TextObservation(
                text: "Contact sam@example.com and use sk_live_1234567890abcdef123456",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ]

        let detections = SensitiveTextDetector().detections(in: observations)

        XCTAssertTrue(detections.contains { $0.kind == .email })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "Stripe secret key" })
    }

    func testDetectsP0SensitiveTextCategories() {
        let text = """
        Contact sam@example.com or +1 (415) 555-0134 from 10.10.12.8.
        Card 4242 4242 4242 4242.
        AWS AKIAIOSFODNN7EXAMPLE GitHub ghp_1234567890abcdefghijklMNOPQR.
        Google AIzaSyA1234567890abcdefGHIJKLMNopqrsTuv OpenAI sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz1234567890.
        Slack \(SyntheticDetectorValues.slackBotToken) Stripe sk_live_1234567890abcdef123456.
        Authorization: Bearer tokenValue123ABCdef456.
        JWT eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.Signature123.
        DATABASE_PASSWORD=correctHorse9Battery!
        https://example.com/callback?access_token=urlToken1234567890abcdef&state=ok
        """

        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            )
        ])

        XCTAssertTrue(detections.contains { $0.kind == .email && $0.label == "Email" })
        XCTAssertTrue(detections.contains { $0.kind == .phoneNumber && $0.label == "Phone number" })
        XCTAssertTrue(detections.contains { $0.kind == .ipAddress && $0.label == "IP address" })
        XCTAssertTrue(detections.contains { $0.kind == .creditCard && $0.label == "Card number" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "AWS key" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "GitHub token" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "Google API key" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "OpenAI API key" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "Slack token" })
        XCTAssertTrue(detections.contains { $0.kind == .apiKey && $0.label == "Stripe secret key" })
        XCTAssertTrue(detections.contains { $0.kind == .secret && $0.label == "Bearer token" })
        XCTAssertTrue(detections.contains { $0.kind == .secret && $0.label == "JWT" })
        XCTAssertTrue(detections.contains { $0.kind == .secret && $0.label == "Environment secret" })
        XCTAssertTrue(detections.contains { $0.kind == .url && $0.label == "URL query token" })
    }

    func testStructuredMetadataUsesReadableLabelsAndMatchedValueRanges() throws {
        let text = "DATABASE_PASSWORD='correctHorse9Battery!' https://example.com/?access_token=urlToken1234567890abcdef"
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let envSecret = try XCTUnwrap(detections.first { $0.label == "Environment secret" })
        XCTAssertEqual(envSecret.kind, .secret)
        XCTAssertEqual(envSecret.source, .deterministic)
        XCTAssertEqual(envSecret.matchedText, "correctHorse9Battery!")
        XCTAssertEqual(envSecret.matchedRange, TextRange((text as NSString).range(of: "correctHorse9Battery!")))
        XCTAssertEqual(envSecret.suggestedAction, .redact)
        XCTAssertFalse(envSecret.reason.contains("regex"))

        let urlToken = try XCTUnwrap(detections.first { $0.label == "URL query token" })
        XCTAssertEqual(urlToken.kind, .url)
        XCTAssertEqual(urlToken.matchedText, "urlToken1234567890abcdef")
        XCTAssertEqual(urlToken.matchedRange, TextRange((text as NSString).range(of: "urlToken1234567890abcdef")))
        XCTAssertFalse(urlToken.reason.contains("regex"))
    }

    func testUsesSubstringBoundsWhenObservationProvidesResolver() throws {
        let text = "Contact sam@example.com before sharing"
        let emailRange = (text as NSString).range(of: "sam@example.com")
        let emailBounds = CGRect(x: 0.3, y: 0.7, width: 0.22, height: 0.1)
        let observations = [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
                boundsResolver: { nsRange in
                    nsRange == emailRange ? emailBounds : nil
                }
            )
        ]

        let detections = SensitiveTextDetector().detections(in: observations)
        let email = try XCTUnwrap(detections.first { $0.kind == .email })

        XCTAssertEqual(email.normalizedBounds, emailBounds)
        XCTAssertEqual(email.boundsPrecision, .tight)
        XCTAssertEqual(email.matchedText, "sam@example.com")
        XCTAssertEqual(email.matchedRange, TextRange(emailRange))
        XCTAssertEqual(email.suggestedAction, .redact)
        XCTAssertLessThan(email.normalizedBounds.width, observations[0].normalizedBounds.width)
    }

    func testFallsBackToLineBoundsAtReviewConfidenceWhenSubstringBoundsAreUnavailable() throws {
        let lineBounds = CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
        let observations = [
            TextObservation(
                text: "Contact sam@example.com before sharing",
                normalizedBounds: lineBounds
            )
        ]

        let email = try XCTUnwrap(SensitiveTextDetector().detections(in: observations).first { $0.kind == .email })

        XCTAssertEqual(email.normalizedBounds, lineBounds)
        XCTAssertEqual(email.boundsPrecision, .lineFallback)
        XCTAssertLessThanOrEqual(email.confidence, 0.74)
        XCTAssertEqual(email.suggestedAction, .redact)
    }

    func testLowConfidenceOCRProducesReviewableDetection() throws {
        let text = "Contact sam@example.com before sharing"
        let emailRange = (text as NSString).range(of: "sam@example.com")
        let emailBounds = CGRect(x: 0.30, y: 0.70, width: 0.22, height: 0.10)
        let observations = [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.80, height: 0.10),
                confidence: 0.42,
                boundsResolver: { nsRange in
                    nsRange == emailRange ? emailBounds : nil
                }
            )
        ]

        let email = try XCTUnwrap(SensitiveTextDetector().detections(in: observations).first { $0.kind == .email })

        XCTAssertEqual(email.normalizedBounds, emailBounds)
        XCTAssertEqual(email.boundsPrecision, .tight)
        XCTAssertEqual(email.confidence, 0.42)
        XCTAssertEqual(email.suggestedAction, .review)
    }

    func testDetectsLuhnValidCardOnly() {
        let observations = [
            TextObservation(
                text: "Valid 4242 4242 4242 4242 Invalid 4242 4242 4242 4241",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ]

        let detections = SensitiveTextDetector().detections(in: observations)

        XCTAssertEqual(detections.filter { $0.kind == .creditCard }.count, 1)
    }

    func testAvoidsNoisyNumberAndPlaceholderFixtures() {
        let text = """
        Order ORDER-20260617-00012345 shipped at 2026-06-17 09:36:34.
        UUID 550e8400-e29b-41d4-a716-446655440000.
        CUSTOMER_ID=customer_01HZYXWVUTSRQPONMLKJIHGFED.
        API_KEY=changeme
        Bare digits 4155550134 should not be enough.
        Invalid card 4242 4242 4242 4241.
        """

        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertFalse(detections.contains { $0.kind == .creditCard })
        XCTAssertFalse(detections.contains { $0.kind == .phoneNumber })
        XCTAssertFalse(detections.contains { $0.label == "Environment secret" })
        XCTAssertFalse(detections.contains { $0.label == "High-entropy secret" })
    }

    func testPhoneDetectorRejectsSpreadsheetNumericMeasurements() {
        let text = """
        361 30940 199 299087
        405 70346 263 54089
        320 132181 183 2565799
        2589.728223 228202931 599.456446 3144110896 576.3379
        1181173960002.31 1100.053973
        136797717982.45 127.4028029
        1812070519848.31 247.21317345
        3664362413.05
        281061004732.66
        47016897118
        3180.25012 GB
        3.105713008 TB
        0.908642892 GB per day per MVS
        27.25928675 GB per month per 1 MVS
        95407.50361 GB
        1144890.043 GB
        1118.06 TB
        """

        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            )
        ])

        XCTAssertFalse(detections.contains { $0.kind == .phoneNumber })
    }

    func testPhoneDetectorKeepsFormattedPhonesAndRequiresContextForSpaceOnlyPhones() {
        let text = """
        Office 415.555.0134
        Hotline 415-555-0135
        Call 415 555 0136
        Spreadsheet row 415 555 0137
        """

        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            )
        ])

        XCTAssertTrue(detections.contains { $0.kind == .phoneNumber && $0.matchedText == "415.555.0134" })
        XCTAssertTrue(detections.contains { $0.kind == .phoneNumber && $0.matchedText == "415-555-0135" })
        XCTAssertTrue(detections.contains { $0.kind == .phoneNumber && $0.matchedText == "415 555 0136" })
        XCTAssertFalse(detections.contains { $0.kind == .phoneNumber && $0.matchedText == "415 555 0137" })
    }

    func testHighEntropyDetectionIsMediumConfidenceAndReviewOnly() throws {
        let token = "aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK"
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: "Generated token \(token)",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let entropySecret = try XCTUnwrap(detections.first { $0.label == "High-entropy secret" })
        XCTAssertEqual(entropySecret.kind, .secret)
        XCTAssertEqual(entropySecret.matchedText, token)
        XCTAssertEqual(entropySecret.suggestedAction, .review)
        XCTAssertLessThan(entropySecret.confidence, 0.8)
    }

    func testDetectorCategoryPreferencesSuppressSelectedTextFamilies() {
        var preferences = DetectorCategoryPreferences.allEnabled
        preferences.setEnabled(false, for: .emails)
        preferences.setEnabled(false, for: .highEntropy)
        let configuration = CustomDetectionConfiguration(detectorCategoryPreferences: preferences)
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            TextObservation(
                text: "Email sam@example.com token aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK card 4242 4242 4242 4242",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertFalse(detections.contains { $0.kind == .email })
        XCTAssertFalse(detections.contains { $0.label == "High-entropy secret" })
        XCTAssertTrue(detections.contains { $0.kind == .creditCard })
    }

    func testDetectorCategoryPreferencesSuppressEachTextFamily() {
        let cases: [(category: DetectorCategory, label: String, text: String, configuration: CustomDetectionConfiguration)] = [
            (.emails, "Email", "Email sam@example.com", .empty),
            (.phones, "Phone number", "Phone +1 (415) 555-0134", .empty),
            (.cards, "Card number", "Card 4242 4242 4242 4242", .empty),
            (.ipAddresses, "IP address", "Host 10.10.12.8", .empty),
            (.secrets, "AWS key", "AWS AKIAIOSFODNN7EXAMPLE", .empty),
            (.highEntropy, "High-entropy secret", "Generated token aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK", .empty),
            (.customerAccount, "Account/customer ID", "Customer customer_01HZYXWVUTSRQPONMLKJIHGFED", .empty),
            (
                .custom,
                "Custom term",
                "Project DevanAlpha is visible",
                CustomDetectionConfiguration(terms: ["DevanAlpha"])
            )
        ]

        for testCase in cases {
            var enabledConfiguration = testCase.configuration
            var enabledPreferences = enabledConfiguration.detectorCategoryPreferences
            enabledPreferences.setEnabled(true, for: testCase.category)
            enabledConfiguration.detectorCategoryPreferences = enabledPreferences

            let enabledDetections = SensitiveTextDetector(customConfiguration: enabledConfiguration).detections(in: [
                TextObservation(
                    text: testCase.text,
                    normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
                )
            ])
            XCTAssertTrue(
                enabledDetections.contains { $0.label == testCase.label },
                "Expected \(testCase.label) before disabling \(testCase.category)."
            )

            var disabledConfiguration = testCase.configuration
            var disabledPreferences = disabledConfiguration.detectorCategoryPreferences
            disabledPreferences.setEnabled(false, for: testCase.category)
            disabledConfiguration.detectorCategoryPreferences = disabledPreferences

            let disabledDetections = SensitiveTextDetector(customConfiguration: disabledConfiguration).detections(in: [
                TextObservation(
                    text: testCase.text,
                    normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
                )
            ])
            XCTAssertFalse(
                disabledDetections.contains { $0.label == testCase.label },
                "Expected \(testCase.label) to disappear after disabling \(testCase.category)."
            )
        }
    }

    func testHighEntropyIgnoresDeploymentTagsAndPathsButPreservesSecretContext() {
        let deploymentTag = "master-2023-02-23-20.25.51-18d5643"
        let logPath = "/mnt/bluemeta/db2/database/db2inst1/NODE0000/SQL00001/LOGSTREAM0000"
        let metricIdentifier = "MSK_MaxOffsetLag_analyticsDataProcessorConsumerGroup_risk_for_llm_01"
        let meetingURL = "https://ibm.webex.com/meet/devans"
        let calendarURL = "https://example.webex.com/meeting/8xK2-safe-team-sync-2026"
        let safeDetections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: """
                GI-Tag: \(deploymentTag)
                Path to log files \(logPath)
                Metric \(metricIdentifier)
                Team meeting \(meetingURL)
                Calendar link \(calendarURL)
                """,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertFalse(safeDetections.contains { $0.label == "High-entropy secret" && $0.matchedText == deploymentTag })
        XCTAssertFalse(safeDetections.contains { $0.label == "High-entropy secret" && $0.matchedText == logPath })
        XCTAssertFalse(safeDetections.contains { $0.label == "High-entropy secret" && $0.matchedText == metricIdentifier })
        XCTAssertFalse(safeDetections.contains { $0.label == "High-entropy secret" && $0.matchedText == meetingURL })
        XCTAssertFalse(safeDetections.contains { $0.label == "High-entropy secret" && ($0.matchedText?.contains("8xK2-safe-team-sync") == true) })
        XCTAssertFalse(safeDetections.contains { $0.label == "URL query token" })

        let secretValue = "aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK"
        let secretDetections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: "api_key = \(secretValue)",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertTrue(secretDetections.contains { $0.label == "High-entropy secret" && $0.matchedText == secretValue })
    }

    func testCustomerAccountDetectorSuppressesInfrastructureResourceNames() {
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: """
                tenant-fetcher-db2-create-partition
                tenant-fetcher-db2-drop-partitions
                workspace-scheduler-cronjob-12345
                tenant-fetcher-load-aggregate-tables
                """,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertFalse(detections.contains { $0.label == "Account/customer ID" })
    }

    func testDetectsAccountCustomerIdentifiersAsReviewOnly() throws {
        let customerID = "customer_01HZYXWVUTSRQPONMLKJIHGFED"
        let accountID = "acct_9KLMNOPQRSTUV1234"
        let tenantID = "tenant-9KLMNOPQRSTUV1234"
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: "Customer \(customerID) maps to account \(accountID). Tenant ID \(tenantID).",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let customerDetection = try XCTUnwrap(detections.first { $0.label == "Account/customer ID" && $0.matchedText == customerID })
        XCTAssertEqual(customerDetection.kind, .unknown)
        XCTAssertEqual(customerDetection.suggestedAction, .review)
        XCTAssertLessThan(customerDetection.confidence, 0.8)

        XCTAssertTrue(detections.contains { $0.label == "Account/customer ID" && $0.matchedText == accountID })
        XCTAssertTrue(detections.contains { $0.label == "Account/customer ID" && $0.matchedText == tenantID })
        XCTAssertFalse(detections.contains { $0.label == "High-entropy secret" && $0.matchedText == customerID })
    }

    func testDetectsWholeSSHPublicKeyMaterialAsReviewFinding() throws {
        let publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCnsRWx2vi6iJYyUFuttSzpKvjuelihxtHk5Mgn1UJf9a6fhN3k3meOr9aVUOAJu3Rjhm1V2aEqSGTJ4sXguPhhxbXO4"
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: #""sshAuthorizedKeys": ["\#(publicKey)"]"#,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let detection = try XCTUnwrap(detections.first { $0.label == "SSH public key" })
        XCTAssertEqual(detection.matchedText, publicKey)
        XCTAssertEqual(detection.suggestedAction, .review)
        XCTAssertFalse(detections.contains { $0.label == "High-entropy secret" && $0.matchedText != publicKey })
    }

    func testDetectsWrappedSSHPublicKeyMaterialAsReviewFinding() throws {
        let wrappedPublicKey = """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCnsRWx2vi6iJYyUFuttSzpKvjuelihxtHk5Mgn1UJf9a6fhN3k3meOr9aVUOAJu3Rjhm1V2aEq
        SGTJ4sXguPhhxbXO4ohcv75hxTb7DeU51BEDAG3n2mXMIkjhaOLIqm2diqOHicXErAVzE87mX8qMiHaZf02KY2UROF8g0qDOIq9xrrbY82sKEIrC
        """
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: #""sshAuthorizedKeys": ["\#(wrappedPublicKey)"]"#,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let detection = try XCTUnwrap(detections.first { $0.label == "SSH public key" })
        XCTAssertTrue(detection.matchedText?.contains("ssh-rsa") == true)
        XCTAssertEqual(detection.suggestedAction, .review)
    }

    func testNestedTokenMatchesResolveToHigherSignalDetection() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.Signature123"
        let bearerDetections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: "Authorization: Bearer \(jwt)",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertTrue(bearerDetections.contains { $0.label == "Bearer token" })
        XCTAssertFalse(bearerDetections.contains { $0.label == "JWT" })

        let urlToken = "aZ9qLmN8pQrS7tUvWxY6zAbCdEfGhIjK"
        let urlDetections = SensitiveTextDetector().detections(in: [
            TextObservation(
                text: "Open https://example.com?access_token=\(urlToken)",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertTrue(urlDetections.contains { $0.label == "URL query token" })
        XCTAssertFalse(urlDetections.contains { $0.label == "High-entropy secret" })
    }

    func testCustomTermsProduceLocalDetections() throws {
        let configuration = CustomDetectionConfiguration(terms: ["Project Monarch"])
        let text = "Do not share Project Monarch outside the launch review."
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let custom = try XCTUnwrap(detections.first { $0.label == "Custom term" })
        XCTAssertEqual(custom.kind, .unknown)
        XCTAssertEqual(custom.source, .deterministic)
        XCTAssertEqual(custom.reason, "Matched a local custom term.")
        XCTAssertEqual(custom.matchedText, "Project Monarch")
        XCTAssertEqual(custom.matchedRange, TextRange((text as NSString).range(of: "Project Monarch")))
        XCTAssertEqual(custom.suggestedAction, .redact)
    }

    func testCustomRegexesProduceLocalDetections() throws {
        let configuration = CustomDetectionConfiguration(regexes: [#"CUST-[0-9]{4}"#])
        let text = "Customer CUST-4912 appears in the screenshot."
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            TextObservation(
                text: text,
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        let custom = try XCTUnwrap(detections.first { $0.label == "Custom pattern" })
        XCTAssertEqual(custom.kind, .unknown)
        XCTAssertEqual(custom.reason, "Matched a local custom pattern.")
        XCTAssertEqual(custom.matchedText, "CUST-4912")
    }

    func testInvalidCustomRegexesAreReportedAndIgnored() {
        let configuration = CustomDetectionConfiguration(regexes: ["(", #"TICKET-[0-9]+"#])
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            TextObservation(
                text: "Escalate TICKET-3498 today.",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertEqual(configuration.invalidRegexPatterns, ["("])
        XCTAssertEqual(detections.filter { $0.label == "Custom pattern" }.count, 1)
        XCTAssertEqual(detections.first { $0.label == "Custom pattern" }?.matchedText, "TICKET-3498")
    }

    func testAllowlistSuppressesDefaultAndCustomDetections() {
        let configuration = CustomDetectionConfiguration(
            terms: ["Project Monarch"],
            allowlist: ["sam@example.com", "Project Monarch"]
        )
        let detections = SensitiveTextDetector(customConfiguration: configuration).detections(in: [
            TextObservation(
                text: "Safe sam@example.com, redact jane@example.com, ignore Project Monarch.",
                normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
            )
        ])

        XCTAssertFalse(detections.contains { $0.matchedText == "sam@example.com" })
        XCTAssertTrue(detections.contains { $0.matchedText == "jane@example.com" })
        XCTAssertFalse(detections.contains { $0.label == "Custom term" })
    }

    func testConvertsVisionBoundsToPixelRect() {
        let rect = RedactionRenderer.pixelRect(
            for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(rect, CGRect(x: 250, y: 400, width: 500, height: 200))
    }

    func testOutwardPixelRectCoversFractionalEdges() {
        let rect = RedactionRenderer.outwardPixelRect(
            for: CGRect(x: 0.101, y: 0.251, width: 0.199, height: 0.249),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(rect, CGRect(x: 101, y: 200, width: 199, height: 200))
    }

    func testRedactionPlanPrefersTightOverLineFallbackOverlap() {
        let line = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.74,
            normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
            source: .deterministic,
            reason: "Line fallback.",
            matchedText: "sam@example.com",
            matchedRange: TextRange(location: 8, length: 15),
            boundsPrecision: .lineFallback
        )
        let tight = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.9,
            normalizedBounds: CGRect(x: 0.3, y: 0.7, width: 0.22, height: 0.1),
            source: .deterministic,
            reason: "Tight box.",
            matchedText: "sam@example.com",
            matchedRange: TextRange(location: 8, length: 15),
            boundsPrecision: .tight
        )

        let plan = RedactionPlan(textDetections: [line, tight])

        XCTAssertEqual(plan.detections, [tight])
        XCTAssertEqual(plan.activeDetections, [tight])
    }

    func testRedactionPlanKeepsDistinctFallbackMatchesOnTheSameLine() throws {
        let lineBounds = CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
        let text = "Contact sam@example.com or +1 (415) 555-0134"
        let detections = SensitiveTextDetector().detections(in: [
            TextObservation(text: text, normalizedBounds: lineBounds)
        ])

        let plan = RedactionPlan(textDetections: detections)

        XCTAssertNotNil(plan.detections.first { $0.kind == .email })
        XCTAssertNotNil(plan.detections.first { $0.kind == .phoneNumber })
        XCTAssertEqual(plan.detections.count, 2)
        XCTAssertTrue(plan.detections.allSatisfy { $0.normalizedBounds == lineBounds })
    }

    func testRedactionPlanPrefersManualOverAutomaticOverlap() {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.96,
            normalizedBounds: CGRect(x: 0.20, y: 0.20, width: 0.20, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            matchedText: "sam@example.com",
            matchedRange: TextRange(location: 8, length: 15),
            boundsPrecision: .tight
        )
        let manual = RedactionPlan.manualRedaction(
            bounds: CGRect(x: 0.18, y: 0.18, width: 0.24, height: 0.12)
        )

        let plan = RedactionPlan(textDetections: [automatic], manualDetections: [manual])

        XCTAssertEqual(plan.detections, [manual])
        XCTAssertEqual(plan.activeDetections, [manual])
    }

    func testRedactionPlanMergesSourcesAndHonorsIgnoreDisposition() {
        let text = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.9,
            normalizedBounds: CGRect(x: 0.10, y: 0.80, width: 0.20, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )
        let vision = Detection(
            kind: .face,
            label: "Face",
            confidence: 0.88,
            normalizedBounds: CGRect(x: 0.30, y: 0.55, width: 0.20, height: 0.20),
            source: .vision,
            reason: "Detected face.",
            boundsPrecision: .tight
        )
        let ignoredManual = Detection(
            kind: .unknown,
            label: "Dismissed manual area",
            confidence: 1,
            normalizedBounds: CGRect(x: 0.50, y: 0.20, width: 0.15, height: 0.10),
            source: .user,
            reason: "User-marked area.",
            suggestedAction: .ignore,
            boundsPrecision: .manual
        )

        let plan = RedactionPlan(
            textDetections: [text],
            visionDetections: [vision],
            manualDetections: [ignoredManual]
        )

        XCTAssertEqual(plan.detections, [text, vision, ignoredManual])
        XCTAssertEqual(plan.activeDetections, [text, vision])
    }

    func testRedactionPlanCanDeactivateDetectionForExport() throws {
        let detection = Detection(
            kind: .apiKey,
            label: "API key",
            confidence: 0.98,
            normalizedBounds: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1),
            source: .deterministic,
            reason: "Token.",
            boundsPrecision: .tight
        )

        var plan = RedactionPlan(textDetections: [detection])
        plan.setActive(false, for: detection.id)

        XCTAssertEqual(plan.detections, [detection])
        XCTAssertTrue(plan.activeDetections.isEmpty)
    }

    func testRedactionPlanCanAddUpdateAndRemoveManualRedaction() throws {
        var plan = RedactionPlan.empty

        let id = try XCTUnwrap(plan.addManualRedaction(
            bounds: CGRect(x: -0.10, y: 0.20, width: 0.30, height: 0.12)
        ))

        let added = try XCTUnwrap(plan.manualDetections.first)
        XCTAssertEqual(added.id, id)
        XCTAssertEqual(added.source, .user)
        XCTAssertEqual(added.boundsPrecision, .manual)
        assertRect(
            added.normalizedBounds,
            equals: CGRect(x: 0, y: 0.20, width: 0.20, height: 0.12)
        )
        XCTAssertEqual(plan.activeDetections, [added])

        XCTAssertTrue(plan.updateManualRedaction(
            id: id,
            bounds: CGRect(x: 0.42, y: 0.50, width: 0.18, height: 0.16)
        ))
        assertRect(
            try XCTUnwrap(plan.manualDetections.first?.normalizedBounds),
            equals: CGRect(x: 0.42, y: 0.50, width: 0.18, height: 0.16)
        )

        XCTAssertTrue(plan.removeManualRedaction(id: id))
        XCTAssertTrue(plan.manualDetections.isEmpty)
        XCTAssertTrue(plan.activeDetections.isEmpty)
    }

    func testRedactionPlanRejectsTinyManualRedactionsAndAutomaticEdits() {
        let automatic = Detection(
            kind: .email,
            label: "Email",
            confidence: 0.92,
            normalizedBounds: CGRect(x: 0.10, y: 0.70, width: 0.30, height: 0.08),
            source: .deterministic,
            reason: "Detected email address.",
            boundsPrecision: .tight
        )

        var plan = RedactionPlan(textDetections: [automatic])

        XCTAssertNil(plan.addManualRedaction(bounds: CGRect(x: 0.10, y: 0.20, width: 0.001, height: 0.20)))
        XCTAssertFalse(plan.updateManualRedaction(
            id: automatic.id,
            bounds: CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.20)
        ))
        XCTAssertFalse(plan.removeManualRedaction(id: automatic.id))
        XCTAssertEqual(plan.detections, [automatic])
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}
