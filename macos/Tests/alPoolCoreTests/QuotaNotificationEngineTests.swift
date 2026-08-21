import XCTest
@testable import alPoolCore

final class QuotaNotificationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFirstObservationEstablishesBaselineWithoutAlerting() {
        var engine = QuotaNotificationEngine()

        let events = engine.evaluate(
            samples: [sample(usage: 0.90)],
            thresholdAlertsEnabled: true,
            resetAlertsEnabled: true,
            now: now
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testEmitsOnlyHighestThresholdCrossedAndDoesNotRepeatIt() {
        var engine = QuotaNotificationEngine()
        _ = evaluate(&engine, usage: 0.59)

        let caution = evaluate(&engine, usage: 0.61)
        let unchangedBand = evaluate(&engine, usage: 0.70)
        let maximum = evaluate(&engine, usage: 1.0)

        XCTAssertEqual(caution.map(\.kind), [.threshold(.caution)])
        XCTAssertTrue(unchangedBand.isEmpty)
        XCTAssertEqual(maximum.map(\.kind), [.threshold(.maximum)])
    }

    func testEmitsCriticalAlertAtEightyFivePercent() {
        var engine = QuotaNotificationEngine()
        _ = evaluate(&engine, usage: 0.84)

        let events = evaluate(&engine, usage: 0.85)

        XCTAssertEqual(events.map(\.kind), [.threshold(.critical)])
    }

    func testEmitsResetWhenUsageDropsAndResetTimeAdvances() {
        var engine = QuotaNotificationEngine()
        _ = evaluate(&engine, usage: 0.92, resetAt: milliseconds(now.addingTimeInterval(60)))

        let events = evaluate(
            &engine,
            usage: 0.03,
            resetAt: milliseconds(now.addingTimeInterval(5 * 60 * 60))
        )

        XCTAssertEqual(events.map(\.kind), [.reset])
        XCTAssertEqual(events.first?.usage, 0.03)
    }

    func testResetAlertDoesNotAlsoEmitCurrentThreshold() {
        var engine = QuotaNotificationEngine()
        _ = evaluate(&engine, usage: 1.0, resetAt: milliseconds(now.addingTimeInterval(-1)))

        let events = evaluate(
            &engine,
            usage: 0.70,
            resetAt: milliseconds(now.addingTimeInterval(5 * 60 * 60))
        )

        XCTAssertEqual(events.map(\.kind), [.reset])
    }

    func testSmallDropWithUnchangedFutureResetDoesNotLookLikeReset() {
        var engine = QuotaNotificationEngine()
        let resetAt = milliseconds(now.addingTimeInterval(5 * 60 * 60))
        _ = evaluate(&engine, usage: 0.70, resetAt: resetAt)

        let events = evaluate(&engine, usage: 0.68, resetAt: resetAt)

        XCTAssertTrue(events.isEmpty)
    }

    func testDisabledAlertTypesStillAdvanceState() {
        var engine = QuotaNotificationEngine()
        _ = evaluate(&engine, usage: 0.59)
        _ = engine.evaluate(
            samples: [sample(usage: 0.70)],
            thresholdAlertsEnabled: false,
            resetAlertsEnabled: true,
            now: now
        )

        let events = evaluate(&engine, usage: 0.71)

        XCTAssertTrue(events.isEmpty)
    }

    func testPersistedStatePreventsRelaunchReplay() throws {
        var original = QuotaNotificationEngine()
        _ = evaluate(&original, usage: 0.90)
        let data = try JSONEncoder().encode(original.state)
        let restoredState = try JSONDecoder().decode(QuotaNotificationState.self, from: data)
        var restored = QuotaNotificationEngine(state: restoredState)

        let events = evaluate(&restored, usage: 0.91)

        XCTAssertTrue(events.isEmpty)
    }

    func testEnabledAccountSamplesExcludeAbsentWeeklyWindow() throws {
        let data = Data(#"{"name":"unlimited","type":"provider","provider":"zai","enabled":true,"status":"active","refreshDead":false,"inFlight":0,"completedRequests":0,"failedRequests":0,"quota":{"providerSes":0.20,"providerSesReset":2000000000000,"providerWk":0.50,"providerWkReset":2000000000000,"weeklyAbsent":true},"weekly":{"state":"healthy","rawState":"healthy","effectiveUsage":null,"paceState":"unknown"},"usage":{"totalInputTokens":0,"totalOutputTokens":0,"totalRequests":0}}"#.utf8)
        let account = try JSONDecoder().decode(AccountStatus.self, from: data)

        let samples = QuotaSample.enabledAccounts([account])

        XCTAssertEqual(samples.map(\.window), [.fiveHour])
    }

    private func evaluate(
        _ engine: inout QuotaNotificationEngine,
        usage: Double,
        resetAt: Double? = nil
    ) -> [QuotaNotificationEvent] {
        engine.evaluate(
            samples: [sample(usage: usage, resetAt: resetAt)],
            thresholdAlertsEnabled: true,
            resetAlertsEnabled: true,
            now: now
        )
    }

    private func sample(usage: Double, resetAt: Double? = nil) -> QuotaSample {
        .init(accountName: "glm@example.com", window: .weekly, usage: usage, resetAt: resetAt)
    }

    private func milliseconds(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1_000
    }
}
