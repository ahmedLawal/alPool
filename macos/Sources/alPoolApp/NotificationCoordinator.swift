import AppKit
import Foundation
import UserNotifications
import alPoolCore

enum NotificationPermissionState: String {
    case checking = "Checking"
    case notRequested = "Not requested"
    case allowed = "Allowed"
    case denied = "Denied"
}

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionState = NotificationPermissionState.checking
    @Published private(set) var thresholdAlertsEnabled: Bool
    @Published private(set) var resetAlertsEnabled: Bool
    @Published private(set) var lastDeliveryError: String?

    private static let thresholdAlertsKey = "quotaThresholdNotificationsEnabled"
    private static let resetAlertsKey = "quotaResetNotificationsEnabled"
    private static let stateKey = "quotaNotificationState"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var engine: QuotaNotificationEngine

    override convenience init() {
        self.init(center: .current(), defaults: .standard)
    }

    init(center: UNUserNotificationCenter, defaults: UserDefaults) {
        self.center = center
        self.defaults = defaults
        thresholdAlertsEnabled = defaults.object(forKey: Self.thresholdAlertsKey) as? Bool ?? true
        resetAlertsEnabled = defaults.object(forKey: Self.resetAlertsKey) as? Bool ?? true

        if let data = defaults.data(forKey: Self.stateKey),
           let state = try? JSONDecoder().decode(QuotaNotificationState.self, from: data) {
            engine = QuotaNotificationEngine(state: state)
        } else {
            engine = QuotaNotificationEngine()
        }
        super.init()
    }

    func prepare() async {
        center.delegate = self
        await refreshPermissionState()
        if permissionState == .notRequested {
            await requestPermission()
        }
    }

    func refreshPermissionState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            permissionState = .notRequested
        case .denied:
            permissionState = .denied
        case .authorized, .provisional, .ephemeral:
            permissionState = .allowed
        @unknown default:
            permissionState = .checking
        }
    }

    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            lastDeliveryError = nil
        } catch {
            lastDeliveryError = error.localizedDescription
        }
        await refreshPermissionState()
    }

    func setThresholdAlertsEnabled(_ enabled: Bool) {
        thresholdAlertsEnabled = enabled
        defaults.set(enabled, forKey: Self.thresholdAlertsKey)
        requestPermissionIfNeeded(enabled)
    }

    func setResetAlertsEnabled(_ enabled: Bool) {
        resetAlertsEnabled = enabled
        defaults.set(enabled, forKey: Self.resetAlertsKey)
        requestPermissionIfNeeded(enabled)
    }

    func process(_ snapshot: ControlSnapshot) async {
        let samples = QuotaSample.enabledAccounts(snapshot.accounts)
        let events = engine.evaluate(
            samples: samples,
            thresholdAlertsEnabled: thresholdAlertsEnabled,
            resetAlertsEnabled: resetAlertsEnabled
        )
        persistState()

        guard permissionState == .allowed else { return }
        for event in events {
            await deliver(event)
        }
    }

    func sendTestNotification() async {
        if permissionState != .allowed {
            await requestPermission()
        }
        guard permissionState == .allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = "alPool notifications are ready"
        content.body = "You will be notified when quota usage crosses 60%, 85%, or 100%, and when a limit resets."
        content.sound = .default
        await addRequest(identifier: "alpool.quota.test.\(UUID().uuidString)", content: content)
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func requestPermissionIfNeeded(_ enabled: Bool) {
        guard enabled, permissionState == .notRequested else { return }
        Task { await requestPermission() }
    }

    private func persistState() {
        guard let data = try? JSONEncoder().encode(engine.state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }

    private func deliver(_ event: QuotaNotificationEvent) async {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch event.kind {
        case .threshold(let level):
            let percentage = Int((event.usage * 100).rounded())
            content.title = "\(event.window.displayName) quota at \(percentage)%"
            content.body = "\(event.accountName) crossed the \(level.thresholdPercent ?? percentage)% threshold\(resetSuffix(event.resetAt))."
        case .reset:
            let percentage = Int((event.usage * 100).rounded())
            content.title = "\(event.window.displayName) quota reset"
            content.body = "\(event.accountName)'s \(event.window.displayName.lowercased()) usage is now \(percentage)%."
        }

        let identifier = "alpool.quota.\(event.accountName).\(event.window.rawValue).\(Date().timeIntervalSince1970)"
        await addRequest(identifier: identifier, content: content)
    }

    private func addRequest(identifier: String, content: UNMutableNotificationContent) async {
        do {
            try await center.add(.init(identifier: identifier, content: content, trigger: nil))
            lastDeliveryError = nil
        } catch {
            lastDeliveryError = error.localizedDescription
        }
    }

    private func resetSuffix(_ resetAt: Double?) -> String {
        guard let resetAt else { return "" }
        let remaining = max(0, resetAt / 1_000 - Date().timeIntervalSince1970)
        if remaining < 60 { return "; resets in less than a minute" }
        if remaining < 3_600 { return "; resets in \(Int(remaining / 60))m" }
        if remaining < 86_400 { return "; resets in \(Int(remaining / 3_600))h" }
        return "; resets in \(Int(remaining / 86_400))d"
    }
}
