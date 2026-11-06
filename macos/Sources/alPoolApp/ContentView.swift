import Foundation
import SwiftUI
import alPoolCore

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case people = "People"
    case capacity = "Capacity"
    case accounts = "Accounts"
    case routing = "Routing"
    case notifications = "Notifications"
    case updates = "Updates"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .activity: "waveform.path.ecg"
        case .people: "person.3"
        case .capacity: "fuelpump"
        case .accounts: "person.2"
        case .routing: "arrow.triangle.branch"
        case .notifications: "bell"
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
                    case .people: PeopleView(snapshot: snapshot)
                    case .capacity: CapacityView(snapshot: snapshot)
                    case .accounts: AccountsView(snapshot: snapshot)
                    case .routing: RoutingView(snapshot: snapshot)
                    case .notifications: NotificationsView(coordinator: model.notifications)
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

private struct NotificationsView: View {
    @ObservedObject var coordinator: NotificationCoordinator

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("System notifications") {
                    Label(coordinator.permissionState.rawValue, systemImage: permissionSymbol)
                        .foregroundStyle(permissionColor)
                }

                if coordinator.permissionState == .denied {
                    Button("Open notification settings") {
                        coordinator.openNotificationSettings()
                    }
                } else if coordinator.permissionState == .notRequested {
                    Button("Allow notifications") {
                        Task { await coordinator.requestPermission() }
                    }
                }

                Button("Send test notification") {
                    Task { await coordinator.sendTestNotification() }
                }
                .disabled(coordinator.permissionState == .denied)
            }

            Section("Quota alerts") {
                Toggle("Threshold alerts", isOn: Binding(
                    get: { coordinator.thresholdAlertsEnabled },
                    set: { enabled in coordinator.setThresholdAlertsEnabled(enabled) }
                ))
                Text("Notify when an enabled account crosses 60%, 85%, or 100% usage in its 5-hour or weekly window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Reset alerts", isOn: Binding(
                    get: { coordinator.resetAlertsEnabled },
                    set: { enabled in coordinator.setResetAlertsEnabled(enabled) }
                ))
                Text("Notify when alPool confirms that a quota window has rolled over and usage has dropped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("alPool checks quota with the existing two-second backend snapshot. Alerts are deduplicated across app relaunches. Closing the window keeps alerts active; quitting alPool stops them.")
                    .foregroundStyle(.secondary)
                if let error = coordinator.lastDeliveryError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task { await coordinator.refreshPermissionState() }
    }

    private var permissionSymbol: String {
        switch coordinator.permissionState {
        case .allowed: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle.fill"
        case .checking, .notRequested: "clock"
        }
    }

    private var permissionColor: Color {
        switch coordinator.permissionState {
        case .allowed: .green
        case .denied: .red
        case .checking, .notRequested: .orange
        }
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
    @AppStorage("overviewHideMaxed") private var hideMaxed = false

    private var enabledAccounts: [AccountStatus] {
        snapshot.accounts.filter(\.enabled).filter { $0.poolBenchedBy == nil }
    }

    private var visibleAccounts: [AccountStatus] {
        guard hideMaxed else { return enabledAccounts }
        return enabledAccounts.filter { account in
            // Unknown quota (nil) never hides an account — only a reading that
            // has actually reached the limit does. Fractions can exceed 1.0.
            (account.quota.sessionUsage ?? 0) < 0.999 && (account.quota.weeklyUsage ?? 0) < 0.999
        }
    }

    private var hiddenCount: Int { enabledAccounts.count - visibleAccounts.count }

    private var density: OverviewAccountDensity {
        OverviewAccountDensity(rawValue: densityValue) ?? .detailed
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                MetricCard(title: "Accounts", value: "\(snapshot.accounts.filter(\.enabled).filter { $0.poolBenchedBy == nil }.count) enabled", symbol: "person.2")
                MetricCard(title: "In flight", value: "\(snapshot.scheduler.globalInFlight)", symbol: "waveform.path.ecg")
                MetricCard(title: "Routing", value: routingLabel(snapshot.routing), symbol: "arrow.triangle.branch")
                MetricCard(title: "Queued", value: "\(snapshot.upstreamThrottle?.queued ?? 0)", symbol: "clock.arrow.circlepath")
            }
            .padding()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text("Accounts").font(.title2.bold())
                    Spacer()
                    Toggle("Hide maxed", isOn: $hideMaxed)
                        .controlSize(.small)
                        .fixedSize()
                    Picker("Account detail", selection: $densityValue) {
                        Text("Compact").tag(OverviewAccountDensity.compact.rawValue)
                        Text("Detailed").tag(OverviewAccountDensity.detailed.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    SafetyLegend()
                }
                ForEach(visibleAccounts) { account in
                    AccountCard(account: account, density: density, hidesRoutineStatus: true)
                }
                if hideMaxed && hiddenCount > 0 {
                    Text(hiddenCount == 1
                         ? "1 account hidden — 5-hour or weekly limit reached"
                         : "\(hiddenCount) accounts hidden — 5-hour or weekly limit reached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text(ActivityTimeFormatter.localTime(event.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private func durationLabel(_ milliseconds: Double) -> String {
    if milliseconds < 1_000 { return "\(Int(milliseconds)) ms" }
    return String(format: "%.1f s", milliseconds / 1_000)
}

private enum CapacityWindow: String {
    case session
    case weekly
}

private struct CapacityView: View {
    let snapshot: ControlSnapshot
    @AppStorage("capacityWindow") private var windowValue = CapacityWindow.weekly.rawValue

    private var window: CapacityWindow {
        CapacityWindow(rawValue: windowValue) ?? .weekly
    }

    private var enabledAccounts: [AccountStatus] {
        snapshot.accounts.filter(\.enabled).filter { $0.poolBenchedBy == nil }
    }

    var body: some View {
        List {
            Section {
                Picker("Capacity window", selection: $windowValue) {
                    Text("5 hour").tag(CapacityWindow.session.rawValue)
                    Text("Weekly").tag(CapacityWindow.weekly.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Enabled accounts") {
                ForEach(enabledAccounts) { account in
                    CapacityAccountRow(account: account, window: window)
                }
            }

            Section {
                Text("The $/1M metric compares monthly plan price against estimated weekly capacity. It is not a provider billing rate. Capacity is estimated in tokens from observed usage: tokens delivered divided by how full the provider reported the window. Completed windows become measured samples; low-confidence readings are withheld.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capacity")
    }
}

private struct CapacityAccountRow: View {
    let account: AccountStatus
    let window: CapacityWindow

    private var info: CapacityWindowInfo? {
        switch window {
        case .session: account.capacity?.session
        case .weekly: account.capacity?.weekly
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name).font(.headline)
                Text("· \(account.providerLabel) · \(account.locationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if info?.derived == true {
                    Label("Derived", systemImage: "function")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 28) {
                CapacityMetric(label: "Estimated $/1M", value: account.pricePerMillionWeeklyTokens.map { String(format: "$%.2f", $0) } ?? "—")
                CapacityMetric(label: "Plan / month", value: account.monthlyPriceUSD.map { String(format: "$%.2f", $0) } ?? "—")
            }
            if hasCapacityData {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                    GridRow {
                        CapacityMetric(label: info?.derived == true ? "Estimated" : "Current", value: tokenCountLabel(info?.current), lowerBound: info?.current != nil && info?.lowerBound == true)
                        CapacityMetric(label: "Latest measured", value: tokenCountLabel(info?.latest))
                        CapacityMetric(label: "Measured average", value: tokenCountLabel(info?.average))
                        CapacityMetric(label: "Samples", value: "\(info?.samples ?? 0)")
                    }
                }
                if info?.derived == true {
                    Text("No weekly limit · estimated from measured 5-hour capacity × 33.6")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let usage = info?.usage {
                    Text("Current window \(usage.formatted(.percent.precision(.fractionLength(0)))) full")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var hasCapacityData: Bool {
        info?.current != nil || info?.latest != nil || info?.average != nil
    }

    private var emptyMessage: String {
        if window == .weekly, account.quota.weeklyAbsent == true {
            return "Collecting complete 5-hour samples for the weekly estimate"
        }
        return "Collecting usage and completed-window samples"
    }
}

private struct CapacityMetric: View {
    let label: String
    let value: String
    var lowerBound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(lowerBound ? "≥" : "")\(value)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private func tokenCountLabel(_ value: Double?) -> String {
    guard let value, value >= 0 else { return "—" }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
    return String(format: "%.0f", value)
}

private struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: ControlSnapshot
    @State private var renameTarget: AccountStatus?
    @State private var renameValue = ""
    @State private var deleteTarget: AccountStatus?
    @State private var capTarget: AccountStatus?

    var body: some View {
        List(snapshot.accounts.filter { !($0.remote == true && !$0.enabled) }) { account in
            AccountCard(
                account: account,
                showsControls: true,
                canSetCap: snapshot.control.capabilities.setAccountCap == true && account.canManageLocally,
                capAction: { capTarget = account }
            ) {
                Task {
                    await model.send(.init(
                        type: "set-account-enabled",
                        payload: .init(name: account.name, enabled: !account.enabled)
                    ))
                }
            }
            .contextMenu {
                Button("Rename") { renameTarget = account; renameValue = account.name }.disabled(!account.canManageLocally)
                Button("Delete", role: .destructive) { deleteTarget = account }
                    .disabled(!account.canManageLocally || account.runtime == true || account.inFlight > 0)
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
        .sheet(item: $capTarget) { account in
            UsageCapEditor(account: account) { cap in
                Task {
                    await model.send(.init(
                        type: "set-account-cap",
                        payload: .init(name: account.name, capUtilization: cap)
                    ))
                }
                capTarget = nil
            }
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

private struct UsageCapEditor: View {
    let account: AccountStatus
    let onSave: (Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var percent: Int

    init(account: AccountStatus, onSave: @escaping (Double?) -> Void) {
        self.account = account
        self.onSave = onSave
        let existing = account.capUtilization
        _enabled = State(initialValue: existing != nil)
        _percent = State(initialValue: max(1, min(99, Int((existing ?? 0.50) * 100))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Usage cap").font(.title2.bold())
            Text(account.name).foregroundStyle(.secondary)

            Toggle("Reserve capacity on this account", isOn: $enabled)
            if enabled {
                Stepper("Stop routing at \(percent)%", value: $percent, in: 1...99)
                ProgressView(value: Double(percent), total: 100)
            }
            Text(enabled
                 ? "alPool stops placing new requests on this account when either its 5-hour or weekly usage reaches \(percent)%."
                 : "No account-specific cap. Normal routing thresholds apply.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(enabled ? Double(percent) / 100 : nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
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
            ClientRouteSection(snapshot: snapshot)
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
                    ForEach(snapshot.accounts.filter { $0.type != "provider" && $0.enabled && $0.canManageLocally }) { account in
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
                LabeledContent("Running", value: (snapshot.runningVersion ?? snapshot.version?.current).map { "v\($0)" } ?? "Unknown")
                LabeledContent("Latest on GitHub", value: snapshot.version?.latest ?? "Unknown")
                Toggle("Install and apply backend updates automatically", isOn: Binding(
                    get: { snapshot.control.automaticUpdates },
                    set: { enabled in Task { await model.send(.init(type: "set-automatic-updates", payload: .init(enabled: enabled))) } }
                ))
                Button("Check and apply now") { Task { await model.send(.init(type: "check-update")) } }
            }
            Section("Update status") {
                LabeledContent("Status") {
                    Label(selfUpdateLabel, systemImage: selfUpdateSymbol)
                        .foregroundStyle(selfUpdateColor)
                }
                if let checkedAt = snapshot.selfUpdate?.checkedAt {
                    LabeledContent("Last checked", value: ActivityTimeFormatter.shortDateTime(checkedAt))
                }
                if let updatedAt = snapshot.selfUpdate?.updatedAt {
                    LabeledContent("Last updated", value: lastUpdatedLabel(updatedAt))
                }
                if snapshot.selfUpdate?.state == "failed" {
                    Text(snapshot.selfUpdate?.error ?? "The update failed. The running version is still active.")
                        .foregroundStyle(.red)
                } else if let lastFailedAt = snapshot.selfUpdate?.lastFailedAt, let lastError = snapshot.selfUpdate?.lastError {
                    Text("Last failure \(ActivityTimeFormatter.shortDateTime(lastFailedAt)) — \(lastError)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

    private func lastUpdatedLabel(_ updatedAt: String) -> String {
        guard let revision = snapshot.selfUpdate?.toRevision.map({ String($0.prefix(7)) }) else {
            return ActivityTimeFormatter.shortDateTime(updatedAt)
        }
        return "\(ActivityTimeFormatter.shortDateTime(updatedAt)) · main@\(revision)"
    }

    private var selfUpdateLabel: String {
        switch snapshot.selfUpdate?.state {
        case "up-to-date": "Up to date"
        case "update-available": "Update available"
        case "checking": "Checking"
        case "failed": "Update failed"
        default: "Not checked yet"
        }
    }

    private var selfUpdateSymbol: String {
        switch snapshot.selfUpdate?.state {
        case "up-to-date": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        case "checking": "arrow.triangle.2.circlepath"
        case "update-available": "arrow.down.circle.fill"
        default: "clock"
        }
    }

    private var selfUpdateColor: Color {
        switch snapshot.selfUpdate?.state {
        case "up-to-date": .green
        case "failed": .red
        case "checking", "update-available": .orange
        default: .secondary
        }
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
    var canSetCap = false
    var capAction: (() -> Void)?
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
                    Label(account.locationLabel, systemImage: account.remote == true ? "cloud" : "desktopcomputer")
                        .font(.caption2).foregroundStyle(.secondary)
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
                if showsControls, canSetCap, let capAction {
                    Button(capLabel, action: capAction)
                }
                if showsControls, let toggle {
                    Button(account.enabled ? "Disable" : "Enable", action: toggle)
                        .disabled(!account.canManageLocally)
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
                AccountInsights(account: account)
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

    private var capLabel: String {
        guard let cap = account.capUtilization else { return "Set cap" }
        return "Cap \(Int((cap * 100).rounded()))%"
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
