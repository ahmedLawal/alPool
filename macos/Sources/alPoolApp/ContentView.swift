import SwiftUI
import alPoolCore

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case accounts = "Accounts"
    case routing = "Routing"
    case updates = "Updates"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .accounts: "person.2"
        case .routing: "arrow.triangle.branch"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: AppSection? = .overview
    @State private var confirmation: LifecycleConfirmation?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationTitle("alPool")
        } detail: {
            Group {
                if let snapshot = model.snapshot {
                    switch selection ?? .overview {
                    case .overview: OverviewView(snapshot: snapshot)
                    case .accounts: AccountsView(snapshot: snapshot)
                    case .routing: RoutingView(snapshot: snapshot)
                    case .updates: UpdatesView(snapshot: snapshot)
                    }
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Backend unavailable",
                            systemImage: "bolt.horizontal.circle",
                            description: Text(model.lastMessage ?? "Start alPool, then refresh.")
                        )
                        Button("Start backend") { Task { await model.startBackend() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.button, role: confirmation.role) {
                    Task { await model.send(.init(type: confirmation.command)) }
                    self.confirmation = nil
                }
                Button("Cancel", role: .cancel) { self.confirmation = nil }
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await model.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.commandInFlight)

            Button { confirmation = .restart } label: {
                Label("Restart backend", systemImage: "restart")
            }
            .disabled(model.snapshot?.control.capabilities.restart != true)

            Menu {
                Button("Stop backend", role: .destructive) { confirmation = .stop }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.connectionState == "Connected" ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.connectionState)
            if let message = model.lastMessage {
                Text("·")
                Text(message).lineLimit(1)
            }
            Spacer()
            if let pid = model.snapshot?.control.backendPid { Text("Backend \(pid)") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private enum LifecycleConfirmation: Equatable {
    case restart, stop
    var title: String { self == .restart ? "Restart alPool backend?" : "Stop alPool backend?" }
    var button: String { self == .restart ? "Restart" : "Stop" }
    var command: String { self == .restart ? "restart" : "stop" }
    var role: ButtonRole? { self == .stop ? .destructive : nil }
    var message: String {
        self == .restart
            ? "In-flight requests finish on the current worker while a replacement starts."
            : "New requests stop and active requests drain before the backend exits. Closing this app alone never stops it."
    }
}

private struct OverviewView: View {
    let snapshot: ControlSnapshot

    private var enabledAccounts: [AccountStatus] {
        snapshot.accounts.filter(\.enabled)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                MetricCard(title: "Accounts", value: "\(snapshot.accounts.filter(\.enabled).count) enabled", symbol: "person.2")
                MetricCard(title: "In flight", value: "\(snapshot.scheduler.globalInFlight)", symbol: "waveform.path.ecg")
                MetricCard(title: "Routing", value: routingLabel(snapshot.routing), symbol: "arrow.triangle.branch")
                MetricCard(title: "Queued", value: "\(snapshot.upstreamThrottle?.queued ?? 0)", symbol: "clock.arrow.circlepath")
            }
            .padding()

            VStack(alignment: .leading, spacing: 12) {
                Text("Accounts").font(.title2.bold())
                ForEach(enabledAccounts) { account in AccountCard(account: account) }
            }
            .padding([.horizontal, .bottom])
        }
        .navigationTitle("Overview")
    }
}

private struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: ControlSnapshot
    @State private var renameTarget: AccountStatus?
    @State private var renameValue = ""
    @State private var deleteTarget: AccountStatus?

    var body: some View {
        List(snapshot.accounts) { account in
            AccountCard(account: account, showsControls: true) {
                Task {
                    await model.send(.init(
                        type: "set-account-enabled",
                        payload: .init(name: account.name, enabled: !account.enabled)
                    ))
                }
            }
            .contextMenu {
                Button("Rename") { renameTarget = account; renameValue = account.name }
                Button("Delete", role: .destructive) { deleteTarget = account }
                    .disabled(account.runtime == true || account.inFlight > 0)
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            Button("Sync accounts") { Task { await model.send(.init(type: "sync-accounts")) } }
        }
        .sheet(item: $renameTarget) { account in
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename account").font(.title2.bold())
                TextField("Account name", text: $renameValue)
                HStack {
                    Spacer()
                    Button("Cancel") { renameTarget = nil }
                    Button("Rename") {
                        Task {
                            await model.send(.init(type: "rename-account", payload: .init(name: account.name, newName: renameValue)))
                        }
                        renameTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.name ?? "account")?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let account = deleteTarget {
                Button("Delete", role: .destructive) {
                    Task { await model.send(.init(type: "delete-account", payload: .init(name: account.name))) }
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This removes the account from alPool configuration. Provider secrets in GCP are left alone.")
        }
    }
}

private struct RoutingView: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: ControlSnapshot
    private let modes = [
        RoutingModeOption(id: "balance", label: "Balance all", detail: "Score every request across Claude, GLM and Kimi."),
        RoutingModeOption(id: "prefer-claude", label: "Prefer Claude", detail: "Claude first; providers handle overflow."),
        RoutingModeOption(id: "prefer-zai", label: "Prefer GLM", detail: "GLM first; Claude and Kimi handle overflow."),
        RoutingModeOption(id: "prefer-kimi", label: "Prefer Kimi", detail: "Kimi first; Claude and GLM handle overflow."),
        RoutingModeOption(id: "sticky", label: "One account per session", detail: "Keep each session on its starting account."),
    ]

    var body: some View {
        Form {
            Section("Routing mode") {
                ForEach(modes) { mode in
                    Button {
                        Task { await model.send(.init(type: "set-routing-mode", payload: .init(mode: mode.id))) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mode.label).foregroundStyle(.primary)
                                Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if snapshot.routingMode == mode.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }

            Section("Manual Claude preference") {
                Picker("Preferred account", selection: Binding(
                    get: { snapshot.routing.preferredAccount ?? "" },
                    set: { value in Task { await model.send(.init(type: "set-preferred-account", payload: .init(name: value.isEmpty ? nil : value))) } }
                )) {
                    Text("Automatic").tag("")
                    ForEach(snapshot.accounts.filter { $0.type != "provider" && $0.enabled }) { account in
                        Text(account.name).tag(account.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Routing")
    }
}

private struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: ControlSnapshot

    var body: some View {
        Form {
            Section("Backend") {
                LabeledContent("Running", value: snapshot.version?.current.map { "v\($0)" } ?? "Unknown")
                LabeledContent("Fork revision", value: snapshot.version?.latest ?? "Unknown")
                Toggle("Install and apply backend updates automatically", isOn: Binding(
                    get: { snapshot.control.automaticUpdates },
                    set: { enabled in Task { await model.send(.init(type: "set-automatic-updates", payload: .init(enabled: enabled))) } }
                ))
                Button("Check and apply now") { Task { await model.send(.init(type: "check-update")) } }
            }
            Section("MaxPool upstream") {
                LabeledContent("Installed", value: versionLabel(snapshot.upstreamSync?.installedVersion ?? snapshot.version?.current))
                LabeledContent("Latest found", value: versionLabel(snapshot.upstreamSync?.availableVersion))
                LabeledContent("Sync status") {
                    Label(upstreamStatusLabel, systemImage: upstreamStatusSymbol)
                        .foregroundStyle(upstreamStatusColor)
                }
                if snapshot.upstreamSync?.state == "failed" {
                    Text(snapshot.upstreamSync?.error ?? "The upstream update failed. The installed version is still active.")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("The native app is only the IO layer. Backend updates do not replace or rewrite the SwiftUI app.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }

    private func versionLabel(_ version: String?) -> String {
        guard let version, !version.isEmpty else { return "Not checked" }
        return version.hasPrefix("v") ? version : "v\(version)"
    }

    private var upstreamStatusLabel: String {
        switch snapshot.upstreamSync?.state {
        case "up-to-date": "Up to date"
        case "update-available": "Update found"
        case "checking": "Checking"
        case "failed": "Update failed"
        default: "Not checked"
        }
    }

    private var upstreamStatusSymbol: String {
        switch snapshot.upstreamSync?.state {
        case "up-to-date": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        case "checking": "arrow.triangle.2.circlepath"
        default: "clock"
        }
    }

    private var upstreamStatusColor: Color {
        switch snapshot.upstreamSync?.state {
        case "up-to-date": .green
        case "failed": .red
        case "checking", "update-available": .orange
        default: .secondary
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).lineLimit(1)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AccountCard: View {
    let account: AccountStatus
    var showsControls = false
    var toggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.headline)
                    Text("\(account.providerLabel) · \(account.displayStatus)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if account.inFlight > 0 { Label("\(account.inFlight)", systemImage: "waveform") }
                if showsControls, let toggle {
                    Button(account.enabled ? "Disable" : "Enable", action: toggle)
                }
            }
            QuotaRow(label: "5 hour", value: account.quota.sessionUsage, reset: account.quota.sessionReset)
            QuotaRow(
                label: "Weekly",
                value: account.quota.weeklyUsage,
                reset: account.quota.weeklyReset,
                empty: account.quota.weeklyAbsent == true ? "No weekly limit" : "Waiting for quota"
            )
            HStack {
                Text("\(account.usage.totalRequests) requests")
                Text("·")
                Text("\(account.usage.totalInputTokens + account.usage.totalOutputTokens) tokens")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(account.enabled ? 1 : 0.65)
    }
}

private struct QuotaRow: View {
    let label: String
    let value: Double?
    let reset: Double?
    var empty = "Waiting for quota"

    var body: some View {
        HStack {
            Text(label).frame(width: 58, alignment: .leading)
            if let value {
                ProgressView(value: min(max(value, 0), 1))
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Text(resetLabel(reset)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
            } else {
                Text(empty).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.caption)
    }

    private func resetLabel(_ timestamp: Double?) -> String {
        guard let timestamp else { return "" }
        let remaining = max(0, timestamp / 1000 - Date().timeIntervalSince1970)
        if remaining < 60 { return "\(Int(remaining))s" }
        if remaining < 3600 { return "\(Int(remaining / 60))m" }
        if remaining < 86_400 { return "\(Int(remaining / 3600))h" }
        return "\(Int(remaining / 86_400))d"
    }
}

private func routingLabel(_ routing: RoutingInfo) -> String {
    if routing.mode == "preferred", let account = routing.preferredAccount { return "Prefer \(account)" }
    return routing.mode.replacingOccurrences(of: "-", with: " ").capitalized
}

private extension ControlSnapshot {
    var routingMode: String {
        routing.providerMode ?? "balance"
    }
}

private struct RoutingModeOption: Identifiable {
    let id: String
    let label: String
    let detail: String
}
