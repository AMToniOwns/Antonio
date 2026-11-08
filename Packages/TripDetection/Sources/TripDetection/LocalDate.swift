import Foundation

public enum LocalDate {
    public static let uk = TimeZone(identifier: "Europe/London")!

    /// The calendar date (`YYYY-MM-DD`) of `instant` in `timeZone`. This is what the rate engine
    /// sees: a trip belongs to the day it started, in UK local time, across clock changes.
    public static func string(for instant: Date, in timeZone: TimeZone = uk) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        func pad(_ n: Int, _ w: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, w - s.count)) + s
        }
        return "\(pad(c.year!, 4))-\(pad(c.month!, 2))-\(pad(c.day!, 2))"
    }
}
