import Foundation

/// Stable UTC calendar-day bucketing shared by the stats-snapshot and
/// price-history stores. A day bucket is a "yyyy-MM-dd" string in UTC, so the
/// same instant maps to the same bucket regardless of the device timezone.
public enum DayBucket {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
