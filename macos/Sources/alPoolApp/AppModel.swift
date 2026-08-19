import Foundation
import Combine
import Darwin
import alPoolCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: ControlSnapshot?
    @Published private(set) var connectionState = "Connecting"
    @Published private(set) var lastMessage: String?
    @Published private(set) var commandInFlight = false

    private var api: BackendAPI?
    private var pollingTask: Task<Void, Never>?

    deinit { pollingTask?.cancel() }

    func start() async {
        guard pollingTask == nil else { return }
        do {
            let connection = try ConnectionLoader.load()
            api = BackendAPI(connection: connection)
            await refresh()
            pollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    await self?.refresh(silent: true)
                }
            }
        } catch {
            connectionState = "Offline"
            lastMessage = error.localizedDescription
        }
    }

    func refresh(silent: Bool = false) async {
        guard let api else { return }
        do {
            snapshot = try await api.snapshot()
            connectionState = "Connected"
            if !silent { lastMessage = nil }
        } catch {
            connectionState = "Offline"
            if !silent || snapshot == nil { lastMessage = error.localizedDescription }
        }
    }

    func send(_ command: ControlCommand) async {
        guard let api, !commandInFlight else { return }
        commandInFlight = true
        defer { commandInFlight = false }
        do {
            let response = try await api.send(command)
            lastMessage = response.message
            try? await Task.sleep(for: .milliseconds(150))
            await refresh(silent: true)
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func startBackend() async {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/com.ahmedlawal.alpool.backend"]
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                lastMessage = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
            lastMessage = "Starting backend…"
            try? await Task.sleep(for: .seconds(2))
            await refresh()
        } catch {
            lastMessage = error.localizedDescription
        }
    }
}
