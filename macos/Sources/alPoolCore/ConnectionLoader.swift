import Foundation

public enum ConnectionLoaderError: LocalizedError {
    case executableNotFound
    case nodeExecutableNotFound(String)
    case commandFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Could not find the alpool executable. Set ALPOOL_EXECUTABLE or run npm link."
        case .nodeExecutableNotFound(let path):
            "Found alpool at \(path), but could not find Node. Set ALPOOL_NODE_EXECUTABLE or install Node."
        case .commandFailed(let message):
            "Could not read alPool connection details: \(message)"
        case .invalidResponse:
            "alPool returned invalid connection details."
        }
    }
}

public enum ConnectionLoader {
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> BackendConnection {
        if let rawURL = environment["ALPOOL_APP_BASE_URL"],
           let url = URL(string: rawURL),
           let key = environment["ALPOOL_APP_API_KEY"] {
            return BackendConnection(baseURL: url, apiKey: key)
        }

        let alPoolExecutable = try findExecutable(environment: environment)
        let nodeExecutable = try findNodeExecutable(
            beside: alPoolExecutable,
            environment: environment
        )
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = nodeExecutable
        process.arguments = [alPoolExecutable.path, "app-connection"]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            throw ConnectionLoaderError.commandFailed(String(decoding: data, as: UTF8.self))
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let wire = try? JSONDecoder().decode(ConnectionWire.self, from: data),
              let url = URL(string: wire.baseURL) else {
            throw ConnectionLoaderError.invalidResponse
        }
        return BackendConnection(baseURL: url, apiKey: wire.apiKey)
    }

    private static func findExecutable(environment: [String: String]) throws -> URL {
        let manager = FileManager.default
        if let explicit = environment["ALPOOL_EXECUTABLE"], manager.isExecutableFile(atPath: explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let home = manager.homeDirectoryForCurrentUser
        let fixed = [
            "/opt/homebrew/bin/alpool",
            "/usr/local/bin/alpool",
            home.appending(path: ".local/bin/alpool").path,
        ]
        if let path = fixed.first(where: manager.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        let nvmRoot = home.appending(path: ".nvm/versions/node")
        if let versions = try? manager.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil),
           let match = versions
            .map({ $0.appending(path: "bin/alpool") })
            .filter({ manager.isExecutableFile(atPath: $0.path) })
            .sorted(by: { $0.path > $1.path })
            .first {
            return match
        }
        throw ConnectionLoaderError.executableNotFound
    }

    static func findNodeExecutable(
        beside alPoolExecutable: URL,
        environment: [String: String],
        manager: FileManager = .default
    ) throws -> URL {
        if let explicit = environment["ALPOOL_NODE_EXECUTABLE"],
           manager.isExecutableFile(atPath: explicit) {
            return URL(fileURLWithPath: explicit)
        }

        let adjacent = alPoolExecutable.deletingLastPathComponent().appending(path: "node")
        if manager.isExecutableFile(atPath: adjacent.path) {
            return adjacent
        }

        let home = manager.homeDirectoryForCurrentUser
        let fixed = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            home.appending(path: ".local/bin/node").path,
        ]
        if let path = fixed.first(where: manager.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }

        let nvmRoot = home.appending(path: ".nvm/versions/node")
        if let versions = try? manager.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil),
           let match = versions
            .map({ $0.appending(path: "bin/node") })
            .filter({ manager.isExecutableFile(atPath: $0.path) })
            .sorted(by: { $0.path > $1.path })
            .first {
            return match
        }

        throw ConnectionLoaderError.nodeExecutableNotFound(alPoolExecutable.path)
    }

    private struct ConnectionWire: Decodable {
        let baseURL: String
        let apiKey: String
    }
}
