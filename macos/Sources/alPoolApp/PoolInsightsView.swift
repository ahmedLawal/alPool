import SwiftUI
import alPoolCore

struct AccountInsights: View {
    let account: AccountStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let guardedBy = account.poolBenchedBy {
                Label("Handled by \(guardedBy) in the cloud; the local copy does not route.", systemImage: "cloud")
                    .foregroundStyle(.secondary)
            }
            if account.resetCards != nil {
                let cards = account.availableWeeklyCards
                HStack(spacing: 6) {
                    Label("\(cards.count) weekly reset card\(cards.count == 1 ? "" : "s")", systemImage: "arrow.counterclockwise.circle")
                    if let expiry = cards.compactMap(\.expiresAt).min() {
                        Text("· Expires \(Date(timeIntervalSince1970: expiry / 1000).formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .foregroundStyle(.secondary)
            }
            if account.outsideUsage?.outside == true {
                Label("Outside usage detected · reset cards are held", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                if let vendor = account.outsideUsage?.zaiCalls, let pool = account.outsideUsage?.poolCalls {
                    Text("Provider counted \(vendor) calls; this pool sent \(pool) in the compared window.")
                        .foregroundStyle(.secondary)
                }
            }
            if account.outsideUsage?.stale == true {
                Text("Outside-usage reading is stale; the backend will check again.").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

struct PeopleView: View {
    let snapshot: ControlSnapshot
    @State private var period = "d7"

    var body: some View {
        List {
            Picker("Usage window", selection: $period) {
                Text("24 hours").tag("h24")
                Text("7 days").tag("d7")
                Text("30 days").tag("d30")
            }.pickerStyle(.segmented).labelsHidden()

            peopleSection("Local pool", people: snapshot.callerWindows ?? [:])
            ForEach(snapshot.pools ?? []) { pool in
                Section {
                    Label(pool.ok ? "Connected" : "Unavailable", systemImage: pool.ok ? "cloud.fill" : "cloud.slash")
                        .foregroundStyle(pool.ok ? Color.secondary : Color.orange)
                    if let message = pool.lastError, !pool.ok { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text(pool.name) }
                peopleSection("\(pool.name) · People", people: pool.callerWindows ?? [:])
            }
            Section {
                Text("Usage is shown separately for each pool to avoid counting forwarded requests twice. Named callers appear when client identities are configured.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("People")
    }

    private func count(_ windows: PersonWindows, previous: Bool = false) -> PersonCount? {
        switch period {
        case "h24": previous ? windows.h24p : windows.h24
        case "d30": previous ? windows.d30p : windows.d30
        default: previous ? windows.d7p : windows.d7
        }
    }

    @ViewBuilder private func peopleSection(_ title: String, people: [String: PersonWindows]) -> some View {
        Section(title) {
            if people.isEmpty {
                Text("No named callers yet").foregroundStyle(.secondary)
            } else {
                ForEach(people.keys.sorted(), id: \.self) { name in
                    if let windows = people[name] {
                        HStack {
                            Label(name, systemImage: "person.circle").font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(count(windows)?.req ?? 0) requests · \(compactTokens(count(windows)?.tok ?? 0)) tokens")
                                if let previous = count(windows, previous: true) {
                                    let delta = (count(windows)?.req ?? 0) - previous.req
                                    Text("\(delta >= 0 ? "+" : "")\(delta) requests vs previous period")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.monospacedDigit()
                        }.padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

struct ClientRouteSection: View {
    @EnvironmentObject var model: AppModel
    let snapshot: ControlSnapshot
    @State private var confirmDirect = false

    var body: some View {
        Section("Claude Code connection") {
            let gate = snapshot.clientRouting?.gateAvailable == true
            let direct = gate && snapshot.clientRouting?.mode == "direct"
            LabeledContent("Route", value: direct ? "Direct to Anthropic" : "alPool proxy")
            if gate {
                Text("Applies to Claude Code sessions using rc-gate. Changes take effect on their next request.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(direct ? "Use alPool" : "Bypass pool") {
                    if direct { Task { await model.send(.init(type: "set-client-route", payload: .init(mode: "pool"))) } }
                    else { confirmDirect = true }
                }.disabled(model.commandInFlight || snapshot.control.capabilities.setClientRoute != true)
            } else {
                Text("Connected clients use the local alPool proxy. Live pool/direct switching requires rc-gate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Bypass alPool?", isPresented: $confirmDirect, titleVisibility: .visible) {
            Button("Route directly to Anthropic") {
                Task { await model.send(.init(type: "set-client-route", payload: .init(mode: "direct"))) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("rc-gate sessions will stop using the pooled GLM keys. Direct requests need valid Anthropic credentials. Sessions pointing straight at the local proxy remain on alPool.")
        }
    }
}
