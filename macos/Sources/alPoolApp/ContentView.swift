import Foundation
import SwiftUI
import alPoolCore

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case accounts = "Accounts"
    case routing = "Routing"
    case updates = "Updates"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .activity: "waveform.path.ecg"
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
                    case .activity: ActivityView(snapshot: snapshot)
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

private enum OverviewAccountDensity: String {
    case compact
    case detailed
}

private struct OverviewView: View {
    let snapshot: ControlSnapshot
    @AppStorage("overviewAccountDensity") private var densityValue = OverviewAccountDensity.detailed.rawValue

    private var enabledAccounts: [AccountStatus] {
        snapshot.accounts.filter(\.enabled)
    }

    private var density: OverviewAccountDensity {
        OverviewAccountDensity(rawValue: densityValue) ?? .detailed
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
                HStack(spacing: 16) {
                    Text("Accounts").font(.title2.bold())
                    Spacer()
                    Picker("Account detail", selection: $densityValue) {
                        Text("Compact").tag(OverviewAccountDensity.compact.rawValue)
                        Text("Detailed").tag(OverviewAccountDensity.detailed.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    SafetyLegend()
                }
                ForEach(enabledAccounts) { account in
                    AccountCard(account: account, density: density, hidesRoutineStatus: true)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .navigationTitle("Overview")
    }
}

private struct ActivityView: View {
    let snapshot: ControlSnapshot

    private var active: [ActivityRequest] { snapshot.activity?.active ?? [] }
    private var recent: [ActivityEvent] { snapshot.activity?.recent ?? [] }

    var body: some View {
        List {
            Section {
                if active.isEmpty {
                    Text("No requests in flight").foregroundStyle(.secondary)
                } else {
                    ForEach(active) { request in
                        ActiveRequestRow(request: request)
                    }
                }
            } header: {
                Text(inFlightHeader)
            }

            Section("Recent") {
                if recent.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Request routing and backend events appear here as they happen.")
                    )
                } else {
                    ForEach(recent) { event in
                        ActivityEventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .safeAreaInset(edge: .bottom) {
            Text("Updates every 2 seconds. Request bodies and credentials are never shown.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }

    private var inFlightHeader: String {
        let activeCount = snapshot.activity?.activeCount ?? active.count
        let sessionCount = snapshot.activity?.sessionCount ?? 0
        let requests = "\(activeCount) in flight"
        guard sessionCount > 0 else { return requests }
        return "\(requests) · \(sessionCount) session\(sessionCount == 1 ? "" : "s")"
    }
}

private struct ActiveRequestRow: View {
    let request: ActivityRequest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(request.method) \(request.path)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let account = request.account { Text(account) }
                    Text(durationLabel(request.elapsedMs))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ActivityEventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.level == "error" ? "exclamationmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(event.level == "error" ? Color.red : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text(timeLabel(event.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func timeLabel(_ timestamp: String) -> String {
        guard timestamp.count >= 19 else { return timestamp }
        return String(timestamp.dropFirst(11).prefix(8))
    }
}

private func durationLabel(_ milliseconds: Double) -> String {
    if milliseconds < 1_000 { return "\(Int(milliseconds)) ms" }
    return String(format: "%.1f s", milliseconds / 1_000)
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
    var density = OverviewAccountDensity.detailed
    var hidesRoutineStatus = false
    var showsControls = false
    var toggle: (() -> Void)?

    private var visibleStatus: String? {
        let status = account.displayStatus
        return hidesRoutineStatus && status == "Active" ? nil : status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(account.name).font(.headline)
                    Text("·").foregroundStyle(.tertiary)
                    Text(account.providerLabel).font(.caption).foregroundStyle(.secondary)
                    if let visibleStatus {
                        Text("·").foregroundStyle(.tertiary)
                        Text(visibleStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer()
                if account.inFlight > 0 {
                    Label("Serving \(account.inFlight)", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14), in: Capsule())
                        .accessibilityLabel("\(account.inFlight) requests in flight")
                }
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
            if density == .detailed {
                HStack {
                    Text("\(account.usage.totalRequests) requests")
                    Text("·")
                    Text("\(account.usage.totalInputTokens + account.usage.totalOutputTokens) tokens")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(density == .compact ? 12 : 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(account.inFlight > 0 ? Color.green.opacity(0.75) : Color.clear, lineWidth: 1.5)
        }
        .opacity(account.enabled ? 1 : 0.65)
    }
}

private struct SafetyLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            SafetyLegendItem(label: "Safe <60%", color: .green)
            SafetyLegendItem(label: "Caution 60–84%", color: .orange)
            SafetyLegendItem(label: "Critical ≥85%", color: .red)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usage safety: safe below 60 percent, caution from 60 to 84 percent, critical at 85 percent or more")
    }
}

private struct SafetyLegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

private struct QuotaRow: View {
    let label: String
    let value: Double?
    let reset: Double?
    var empty = "Waiting for quota"

    var body: some View {
        HStack {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 68, alignment: .leading)
            if let value {
                ProgressView(value: min(max(value, 0), 1))
                    .tint(quotaSafetyColor(value))
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Text(resetLabel(reset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else {
                Text(empty).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
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

private func quotaSafetyColor(_ usage: Double) -> Color {
    if usage >= 0.85 { return .red }
    if usage >= 0.60 { return .orange }
    return .green
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
