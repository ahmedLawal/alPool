import Foundation

@main struct CheckInsights {
    static func main() throws {
        let base: [String: Any] = [
            "name": "GLM", "type": "provider", "provider": "zai", "enabled": true,
            "status": "active", "refreshDead": false, "inFlight": 0, "completedRequests": 1,
            "failedRequests": 0, "quota": [:],
            "weekly": ["state": "normal", "rawState": "normal", "paceState": "normal"],
            "usage": ["totalInputTokens": 2, "totalOutputTokens": 1, "totalRequests": 1]
        ]
        func account(_ extra: [String: Any] = [:]) throws -> AccountStatus {
            let fields = base.merging(extra) { _, value in value }
            return try JSONDecoder().decode(AccountStatus.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let legacy = try account()
        precondition(legacy.locationLabel == "Local" && legacy.canManageLocally)
        precondition(legacy.pricePerMillionWeeklyTokens == nil)
        let cloud = try account(["remote": true, "poolBenchedBy": "Team"])
        precondition(cloud.locationLabel == "Cloud" && !cloud.canManageLocally)
        precondition(cloud.displayStatus == "Served in cloud")
        let now = Date(timeIntervalSince1970: 1000)
        let cards = try account(["resetCards": ["weekly": [
            ["recordId": 1, "expiresAt": 1001000, "expired": false],
            ["recordId": 2, "expiresAt": 999000, "expired": false],
            ["recordId": 3, "expiresAt": 1001000, "expired": true]
        ]]])
        precondition(cards.availableWeeklyCards(at: now).count == 1)
        let priced = try account(["monthlyPriceUSD": 11, "capacity": ["session": [
            "average": 1000000, "samples": 2, "lowerBound": false, "derived": false
        ]]])
        precondition(abs((priced.weeklyTokenEstimate ?? 0) - 5500000) < 0.01)
        precondition(abs((priced.pricePerMillionWeeklyTokens ?? 0) - 2) < 0.01)
        let unlimited = try account(["quota": ["weeklyAbsent": true], "capacity": ["session": [
            "average": 1000000, "samples": 2, "lowerBound": false, "derived": false
        ]]])
        precondition(abs((unlimited.weeklyTokenEstimate ?? 0) - 33600000) < 0.01)
        let people = try JSONDecoder().decode(PersonWindows.self, from: Data(#"{"d7":{"req":12,"tok":2400},"d7p":{"req":8,"tok":1000}}"#.utf8))
        precondition(people.d7?.req == 12 && people.d7p?.req == 8)
        print("Native insights checks passed: legacy data, cloud controls, expired cards, weekly pricing, unlimited plans, people analytics.")
    }
}
