import XCTest
@testable import alPoolCore

final class ModelsTests: XCTestCase {
    func testDecodesControlSnapshot() throws {
        let data = Data(#"{"activity":{"activeCount":1,"sessionCount":1,"active":[{"id":"7","startedAt":"2026-08-19T12:00:00Z","elapsedMs":1250,"method":"POST","path":"/v1/messages","account":"glm"}],"recent":[{"id":"1","timestamp":"2026-08-19T11:59:00Z","kind":"request","level":"info","message":"POST /v1/messages → glm (200, 1.2s)","method":"POST","path":"/v1/messages","account":"glm","status":200,"durationMs":1200}]},"upstreamSync":{"state":"failed","phase":"merge","checkedAt":"2026-08-19T09:00:00Z","lastSuccessAt":"2026-08-19T03:00:00Z","installedVersion":"1.6.1","installedRevision":"80d5ed4","availableVersion":"1.7.1","availableRevision":"aac169c","error":"The update could not be merged."},"routing":{"mode":"automatic","preferredAccount":null,"providerMode":"balance","crossProviderFallbackPolicy":"always"},"accounts":[],"scheduler":{"mode":"adaptive-least-loaded","globalInFlight":0,"admissionPaused":false},"control":{"generatedAt":"2026-08-18T00:00:00Z","backendPid":42,"automaticUpdates":true,"capabilities":{"setRoutingMode":true,"preferAccount":true,"manageAccounts":true,"addAccounts":false,"syncAccounts":true,"manageUpdates":true,"restart":true,"stop":true}}}"#.utf8)
        let snapshot = try JSONDecoder().decode(ControlSnapshot.self, from: data)
        XCTAssertEqual(snapshot.control.backendPid, 42)
        XCTAssertTrue(snapshot.control.automaticUpdates)
        XCTAssertEqual(snapshot.upstreamSync?.state, "failed")
        XCTAssertEqual(snapshot.upstreamSync?.installedVersion, "1.6.1")
        XCTAssertEqual(snapshot.upstreamSync?.availableVersion, "1.7.1")
        XCTAssertEqual(snapshot.activity?.activeCount, 1)
        XCTAssertEqual(snapshot.activity?.recent.first?.status, 200)
    }

    func testCommandEncodesTypedPayload() throws {
        let command = ControlCommand(type: "set-routing-mode", payload: .init(mode: "prefer-zai"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "set-routing-mode")
        XCTAssertEqual((object?["payload"] as? [String: Any])?["mode"] as? String, "prefer-zai")
    }

    func testDecodesAccountCapacityAndUsageCap() throws {
        let data = Data(#"{"name":"glm","type":"provider","provider":"zai","enabled":true,"capUtilization":0.5,"capacity":{"session":{"current":1200000,"latest":1100000,"average":1150000,"samples":3,"usage":0.42,"source":"live","lowerBound":false,"fresh":true,"derived":false},"weekly":null},"runtime":true,"status":"active","refreshDead":false,"inFlight":0,"completedRequests":4,"failedRequests":0,"lastStatus":200,"lastResponseMs":900,"lastError":null,"cooldownUntil":null,"quota":{"unified5h":null,"unified5hReset":null,"unified7d":null,"unified7dReset":null,"providerSes":0.42,"providerSesReset":1770000000000,"providerWk":null,"providerWkReset":null,"weeklyAbsent":true},"weekly":{"state":"normal","rawState":"normal","effectiveUsage":null,"paceState":"normal"},"usage":{"totalInputTokens":10,"totalOutputTokens":5,"totalRequests":1},"rateLimitedUntil":null}"#.utf8)
        let account = try JSONDecoder().decode(AccountStatus.self, from: data)
        XCTAssertEqual(account.capUtilization, 0.5)
        XCTAssertEqual(account.capacity?.session?.current, 1_200_000)
        XCTAssertEqual(account.capacity?.session?.samples, 3)
    }

    func testCommandEncodesAccountCap() throws {
        let command = ControlCommand(type: "set-account-cap", payload: .init(name: "glm", capUtilization: 0.75))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
        XCTAssertEqual((object?["payload"] as? [String: Any])?["capUtilization"] as? Double, 0.75)
    }

    func testFinderSafeInvocationUsesNodeBesideAlPool() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let alPool = directory.appending(path: "alpool")
        let node = directory.appending(path: "node")
        XCTAssertTrue(FileManager.default.createFile(atPath: alPool.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: node.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: alPool.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        let resolved = try ConnectionLoader.findNodeExecutable(
            beside: alPool,
            environment: [:]
        )
        XCTAssertEqual(resolved.standardizedFileURL, node.standardizedFileURL)
    }

    func testExplicitNodeOverrideWins() throws {
        let node = URL(fileURLWithPath: "/bin/sh")
        let resolved = try ConnectionLoader.findNodeExecutable(
            beside: URL(fileURLWithPath: "/missing/alpool"),
            environment: ["ALPOOL_NODE_EXECUTABLE": node.path]
        )
        XCTAssertEqual(resolved.standardizedFileURL, node.standardizedFileURL)
    }
}
