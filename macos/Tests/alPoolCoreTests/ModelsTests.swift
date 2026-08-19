import XCTest
@testable import alPoolCore

final class ModelsTests: XCTestCase {
    func testDecodesControlSnapshot() throws {
        let data = Data(#"{"routing":{"mode":"automatic","preferredAccount":null,"providerMode":"balance","crossProviderFallbackPolicy":"always"},"accounts":[],"scheduler":{"mode":"adaptive-least-loaded","globalInFlight":0,"admissionPaused":false},"control":{"generatedAt":"2026-08-18T00:00:00Z","backendPid":42,"automaticUpdates":true,"capabilities":{"setRoutingMode":true,"preferAccount":true,"manageAccounts":true,"addAccounts":false,"syncAccounts":true,"manageUpdates":true,"restart":true,"stop":true}}}"#.utf8)
        let snapshot = try JSONDecoder().decode(ControlSnapshot.self, from: data)
        XCTAssertEqual(snapshot.control.backendPid, 42)
        XCTAssertTrue(snapshot.control.automaticUpdates)
    }

    func testCommandEncodesTypedPayload() throws {
        let command = ControlCommand(type: "set-routing-mode", payload: .init(mode: "prefer-zai"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "set-routing-mode")
        XCTAssertEqual((object?["payload"] as? [String: Any])?["mode"] as? String, "prefer-zai")
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
