import Foundation

public struct BackendConnection: Codable, Sendable {
    public let baseURL: URL
    public let apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

public struct ControlSnapshot: Decodable, Sendable {
    public let version: VersionInfo?
    public let upstreamSync: UpstreamSyncInfo?
    public let activity: ActivityInfo?
    public let currentAccount: String?
    public let routing: RoutingInfo
    public let accounts: [AccountStatus]
    public let scheduler: SchedulerInfo
    public let upstreamThrottle: ThrottleInfo?
    public let sessions: SessionInfo?
    public let control: ControlInfo
}

public struct ActivityInfo: Decodable, Sendable {
    public let activeCount: Int
    public let sessionCount: Int
    public let active: [ActivityRequest]
    public let recent: [ActivityEvent]
}

public struct ActivityRequest: Decodable, Identifiable, Sendable {
    public let id: String
    public let startedAt: String
    public let elapsedMs: Double
    public let method: String
    public let path: String
    public let account: String?
}

public struct ActivityEvent: Decodable, Identifiable, Sendable {
    public let id: String
    public let timestamp: String
    public let kind: String
    public let level: String
    public let message: String
    public let method: String?
    public let path: String?
    public let account: String?
    public let status: Int?
    public let durationMs: Double?
}

public struct UpstreamSyncInfo: Decodable, Sendable {
    public let state: String
    public let phase: String?
    public let checkedAt: String?
    public let lastSuccessAt: String?
    public let installedVersion: String?
    public let installedRevision: String?
    public let availableVersion: String?
    public let availableRevision: String?
    public let error: String?
}

public struct VersionInfo: Decodable, Sendable {
    public let current: String?
    public let latest: String?
    public let hasUpdate: Bool?
    public let source: String?
}

public struct RoutingInfo: Decodable, Sendable {
    public let mode: String
    public let preferredAccount: String?
    public let providerMode: String?
    public let crossProviderFallbackPolicy: String?
}

public struct SchedulerInfo: Decodable, Sendable {
    public let mode: String
    public let globalInFlight: Int
    public let admissionPaused: Bool
}

public struct ThrottleInfo: Decodable, Sendable {
    public let active: Bool
    public let until: String?
    public let reason: String?
    public let queued: Int
}

public struct SessionInfo: Decodable, Sendable {
    public let stickyBindings: Int
    public let thinkingProtected: Int
    public let providerPinned: Int
    public let largeContextPinned: Int
}

public struct ControlInfo: Decodable, Sendable {
    public let generatedAt: String
    public let backendPid: Int
    public let automaticUpdates: Bool
    public let capabilities: Capabilities
}

public struct Capabilities: Decodable, Sendable {
    public let setRoutingMode: Bool
    public let preferAccount: Bool
    public let manageAccounts: Bool
    public let addAccounts: Bool
    public let syncAccounts: Bool
    public let manageUpdates: Bool
    public let restart: Bool
    public let stop: Bool
}

public struct AccountStatus: Decodable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let provider: String?
    public let enabled: Bool
    public let runtime: Bool?
    public let status: String
    public let refreshDead: Bool
    public let inFlight: Int
    public let completedRequests: Int
    public let failedRequests: Int
    public let lastStatus: Int?
    public let lastResponseMs: Double?
    public let lastError: String?
    public let cooldownUntil: String?
    public let quota: QuotaInfo
    public let weekly: WeeklyInfo
    public let usage: UsageInfo
    public let rateLimitedUntil: String?

    public var providerLabel: String {
        switch provider {
        case "zai": "z.ai"
        case "kimi": "Moonshot"
        default: type == "provider" ? "Provider" : "Anthropic"
        }
    }

    public var displayStatus: String {
        if !enabled { return "Disabled" }
        if refreshDead { return "Needs login" }
        return status.capitalized
    }
}

public struct QuotaInfo: Decodable, Sendable {
    public let unified5h: Double?
    public let unified5hReset: Double?
    public let unified7d: Double?
    public let unified7dReset: Double?
    public let providerSes: Double?
    public let providerSesReset: Double?
    public let providerWk: Double?
    public let providerWkReset: Double?
    public let weeklyAbsent: Bool?

    public var sessionUsage: Double? { providerSes ?? unified5h }
    public var sessionReset: Double? { providerSesReset ?? unified5hReset }
    public var weeklyUsage: Double? { providerWk ?? unified7d }
    public var weeklyReset: Double? { providerWkReset ?? unified7dReset }
}

public struct WeeklyInfo: Decodable, Sendable {
    public let state: String
    public let rawState: String
    public let effectiveUsage: Double?
    public let paceState: String
}

public struct UsageInfo: Decodable, Sendable {
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalRequests: Int
}

public struct ControlResponse: Decodable, Sendable {
    public let ok: Bool
    public let message: String?
    public let error: ControlAPIError?
}

public struct ControlAPIError: Decodable, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
}

public struct ControlCommand: Encodable, Sendable {
    public struct Payload: Encodable, Sendable {
        public var mode: String?
        public var name: String?
        public var newName: String?
        public var enabled: Bool?
        public var provider: String?
        public var policy: String?

        public init(
            mode: String? = nil,
            name: String? = nil,
            newName: String? = nil,
            enabled: Bool? = nil,
            provider: String? = nil,
            policy: String? = nil
        ) {
            self.mode = mode
            self.name = name
            self.newName = newName
            self.enabled = enabled
            self.provider = provider
            self.policy = policy
        }
    }

    public let type: String
    public let payload: Payload

    public init(type: String, payload: Payload = .init()) {
        self.type = type
        self.payload = payload
    }
}
