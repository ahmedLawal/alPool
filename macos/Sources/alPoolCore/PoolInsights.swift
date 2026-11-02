import Foundation

public struct ClientRoutingInfo: Decodable, Sendable {
    public let mode: String
    public let gateAvailable: Bool
}

public struct ResetCardsInfo: Decodable, Sendable {
    public let weekly: [ResetCard]?
    public let fiveHour: [ResetCard]?
    public let checkedAt: Double?
}

public struct ResetCard: Decodable, Sendable {
    public let recordId: Int?
    public let expiresAt: Double?
    public let expired: Bool?
}

public struct OutsideUsageInfo: Decodable, Sendable {
    public let outside: Bool?
    public let stale: Bool?
    public let checkedAt: Double?
    public let zaiCalls: Int?
    public let poolCalls: Int?
}

public struct PoolInfo: Decodable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let ok: Bool
    public let lastError: String?
    public let callerWindows: [String: PersonWindows]?
}

public struct PersonCount: Decodable, Sendable {
    public let req: Int
    public let tok: Int
}

public struct PersonWindows: Decodable, Sendable {
    public let h24: PersonCount?
    public let h24p: PersonCount?
    public let d7: PersonCount?
    public let d7p: PersonCount?
    public let d30: PersonCount?
    public let d30p: PersonCount?
    public let total: PersonCount?
}

public extension AccountStatus {
    var locationLabel: String { remote == true ? "Cloud" : "Local" }
    var canManageLocally: Bool { remote != true && poolBenchedBy == nil }
    var availableWeeklyCards: [ResetCard] { availableWeeklyCards(at: Date()) }

    func availableWeeklyCards(at date: Date) -> [ResetCard] {
        (resetCards?.weekly ?? []).filter {
            $0.expired != true && ($0.expiresAt.map { $0 > date.timeIntervalSince1970 * 1000 } ?? true)
        }
    }

    var weeklyTokenEstimate: Double? {
        if quota.weeklyAbsent == true {
            guard let session = capacity?.session?.average ?? capacity?.session?.current, session > 0 else { return nil }
            return session * 33.6
        }
        if let weekly = capacity?.weekly?.average ?? capacity?.weekly?.current ?? capacity?.weekly?.latest, weekly > 0 { return weekly }
        if type == "provider", let session = capacity?.session?.average ?? capacity?.session?.current, session > 0 { return session * 5.5 }
        return nil
    }

    // Plan price divided by a weekly tank, matching upstream's comparison metric.
    // This is a capacity estimate, not an invoice or an API billing rate.
    var pricePerMillionWeeklyTokens: Double? {
        guard let price = monthlyPriceUSD, price > 0, price.isFinite,
              let tank = weeklyTokenEstimate, tank > 0, tank.isFinite else { return nil }
        return price / (tank / 1_000_000)
    }
}
