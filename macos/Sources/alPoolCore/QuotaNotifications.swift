import Foundation

public enum QuotaWindow: String, Codable, CaseIterable, Sendable {
    case fiveHour
    case weekly

    public var displayName: String {
        switch self {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        }
    }
}

public enum QuotaAlertLevel: Int, Codable, Comparable, Sendable {
    case safe
    case caution
    case critical
    case maximum

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(usage: Double) {
        if usage >= 0.999 {
            self = .maximum
        } else if usage >= 0.85 {
            self = .critical
        } else if usage >= 0.60 {
            self = .caution
        } else {
            self = .safe
        }
    }

    public var thresholdPercent: Int? {
        switch self {
        case .safe: nil
        case .caution: 60
        case .critical: 85
        case .maximum: 100
        }
    }
}

public struct QuotaSample: Equatable, Sendable {
    public let accountName: String
    public let window: QuotaWindow
    public let usage: Double
    public let resetAt: Double?

    public init(accountName: String, window: QuotaWindow, usage: Double, resetAt: Double?) {
        self.accountName = accountName
        self.window = window
        self.usage = usage
        self.resetAt = resetAt
    }

    public static func enabledAccounts(_ accounts: [AccountStatus]) -> [QuotaSample] {
        accounts.filter(\.enabled).flatMap { account in
            var samples: [QuotaSample] = []
            if let usage = account.quota.sessionUsage {
                samples.append(.init(
                    accountName: account.name,
                    window: .fiveHour,
                    usage: usage,
                    resetAt: account.quota.sessionReset
                ))
            }
            if let usage = account.quota.weeklyUsage, account.quota.weeklyAbsent != true {
                samples.append(.init(
                    accountName: account.name,
                    window: .weekly,
                    usage: usage,
                    resetAt: account.quota.weeklyReset
                ))
            }
            return samples
        }
    }
}

public enum QuotaNotificationKind: Equatable, Sendable {
    case threshold(QuotaAlertLevel)
    case reset
}

public struct QuotaNotificationEvent: Equatable, Sendable {
    public let accountName: String
    public let window: QuotaWindow
    public let kind: QuotaNotificationKind
    public let usage: Double
    public let resetAt: Double?
}

public struct QuotaObservation: Codable, Equatable, Sendable {
    public let usage: Double
    public let resetAt: Double?
}

public struct QuotaNotificationState: Codable, Equatable, Sendable {
    public var observations: [String: QuotaObservation]

    public init(observations: [String: QuotaObservation] = [:]) {
        self.observations = observations
    }
}

public struct QuotaNotificationEngine: Sendable {
    public private(set) var state: QuotaNotificationState

    public init(state: QuotaNotificationState = .init()) {
        self.state = state
    }

    public mutating func evaluate(
        samples: [QuotaSample],
        thresholdAlertsEnabled: Bool,
        resetAlertsEnabled: Bool,
        now: Date = .now
    ) -> [QuotaNotificationEvent] {
        var events: [QuotaNotificationEvent] = []

        for sample in samples {
            let key = observationKey(for: sample)
            let current = QuotaObservation(
                usage: min(max(sample.usage, 0), 1),
                resetAt: sample.resetAt
            )
            defer { state.observations[key] = current }

            guard let previous = state.observations[key] else {
                continue
            }

            if resetDetected(previous: previous, current: current, now: now) {
                if resetAlertsEnabled {
                    events.append(.init(
                        accountName: sample.accountName,
                        window: sample.window,
                        kind: .reset,
                        usage: current.usage,
                        resetAt: current.resetAt
                    ))
                }
                continue
            }

            let previousLevel = QuotaAlertLevel(usage: previous.usage)
            let currentLevel = QuotaAlertLevel(usage: current.usage)
            guard thresholdAlertsEnabled,
                  currentLevel > previousLevel,
                  currentLevel != .safe else {
                continue
            }
            events.append(.init(
                accountName: sample.accountName,
                window: sample.window,
                kind: .threshold(currentLevel),
                usage: current.usage,
                resetAt: current.resetAt
            ))
        }

        return events
    }

    private func observationKey(for sample: QuotaSample) -> String {
        "\(sample.accountName)\u{1F}\(sample.window.rawValue)"
    }

    private func resetDetected(
        previous: QuotaObservation,
        current: QuotaObservation,
        now: Date
    ) -> Bool {
        let drop = previous.usage - current.usage
        guard drop >= 0.01 else { return false }

        let resetAdvanced: Bool
        if let previousReset = previous.resetAt, let currentReset = current.resetAt {
            resetAdvanced = currentReset > previousReset + 60_000
        } else {
            resetAdvanced = false
        }

        let previousResetElapsed = previous.resetAt.map {
            $0 <= now.timeIntervalSince1970 * 1_000 + 30_000
        } ?? false

        let metadataUnavailable = previous.resetAt == nil || current.resetAt == nil
        let unmistakableDropWithoutMetadata = metadataUnavailable && drop >= 0.05

        return resetAdvanced || previousResetElapsed || unmistakableDropWithoutMetadata
    }
}
