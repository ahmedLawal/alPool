import Foundation

public enum ActivityTimeFormatter {
    public static func localTime(
        _ timestamp: String,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date = parse(timestamp) else { return timestamp }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return timestamp
        }

        return String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    private static func parse(_ timestamp: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(timestamp) { return date }
        return try? Date.ISO8601FormatStyle().parse(timestamp)
    }
}
