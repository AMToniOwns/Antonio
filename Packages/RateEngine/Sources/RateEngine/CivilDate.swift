/// A calendar date with no time or time zone, as UK tax rules use it.
///
/// Callers convert a trip's start time to its Europe/London date before handing it
/// to the engine, so the engine itself never touches time zones.
public struct CivilDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        precondition((1...12).contains(month), "month out of range")
        precondition((1...CivilDate.daysIn(month: month, year: year)).contains(day), "day out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`, zero-padded.
    public init?(iso string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...CivilDate.daysIn(month: m, year: y)).contains(d)
        else { return nil }
        self.init(y, m, d)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = CivilDate(iso: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Expected YYYY-MM-DD, got \(string)"))
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// Days since 1970-01-01 (proleptic Gregorian), after Howard Hinnant's `days_from_civil`.
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The date `dayNumber` days after 1970-01-01, after Howard Hinnant's `civil_from_days`.
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public func adding(days: Int) -> CivilDate { CivilDate(dayNumber: dayNumber + days) }

    /// The same date a year later; 29 February moves to 1 March.
    public var oneYearLater: CivilDate {
        month == 2 && day == 29 ? CivilDate(year + 1, 3, 1) : CivilDate(year + 1, month, day)
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// A UK tax year, 6 April to 5 April. `startYear` 2026 is the 2026–27 tax year.
public struct TaxYear: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let startYear: Int

    public init(startYear: Int) { self.startYear = startYear }

    public init(containing date: CivilDate) {
        let beforeSixthApril = date.month < 4 || (date.month == 4 && date.day < 6)
        startYear = beforeSixthApril ? date.year - 1 : date.year
    }

    public var firstDay: CivilDate { CivilDate(startYear, 4, 6) }
    public var lastDay: CivilDate { CivilDate(startYear + 1, 4, 5) }
    public var period: DatePeriod { DatePeriod(uncheckedStart: firstDay, end: lastDay) }

    public var description: String {
        let next = (startYear + 1) % 100
        return "\(startYear)–\(next < 10 ? "0" : "")\(next)"
    }

    public static func < (lhs: TaxYear, rhs: TaxYear) -> Bool { lhs.startYear < rhs.startYear }
}

/// An inclusive range of dates, such as an accounting period.
public struct DatePeriod: Hashable, Sendable {
    public let start: CivilDate
    public let end: CivilDate

    public init(start: CivilDate, end: CivilDate) throws {
        guard start <= end else { throw ClaimError.periodEndsBeforeStart }
        self.start = start
        self.end = end
    }

    init(uncheckedStart start: CivilDate, end: CivilDate) {
        self.start = start
        self.end = end
    }

    /// Number of days, counting both ends.
    public var dayCount: Int { end.dayNumber - start.dayNumber + 1 }

    public func contains(_ date: CivilDate) -> Bool { start <= date && date <= end }

    /// Days this period shares with `other`, counting both ends; 0 if they don't overlap.
    public func overlapDays(with other: DatePeriod) -> Int {
        let lo = max(start, other.start), hi = min(end, other.end)
        return lo <= hi ? hi.dayNumber - lo.dayNumber + 1 : 0
    }

    /// True when the period ends 31 March to 4 April, which HMRC treats as ending on 5 April.
    public var endsOnTaxYearEquivalent: Bool {
        (end.month == 3 && end.day == 31) || (end.month == 4 && end.day <= 5)
    }

    /// Tax years this period touches, earliest first.
    public var taxYears: [TaxYear] {
        let first = TaxYear(containing: start).startYear
        let last = TaxYear(containing: end).startYear
        return (first...last).map(TaxYear.init(startYear:))
    }
}

/// The day and month a business's accounting year ends on. Most sole traders use 5 April or
/// 31 March; HMRC treats any year end from 31 March to 4 April as 5 April.
public struct AccountingYearEnd: Hashable, Codable, Sendable {
    public let month: Int
    public let day: Int

    public static let taxYear = AccountingYearEnd(uncheckedMonth: 4, day: 5)

    public init(month: Int, day: Int) throws {
        // 29 February doesn't exist every year, so it can't be a year end.
        guard (1...12).contains(month), (1...CivilDate.daysIn(month: month, year: 2027)).contains(day) else {
            throw ClaimError.invalidYearEnd
        }
        self.month = month
        self.day = day
    }

    private init(uncheckedMonth month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day))
    }

    private enum CodingKeys: String, CodingKey { case month, day }

    /// The 12-month accounting period that contains `date`.
    public func period(containing date: CivilDate) -> DatePeriod {
        var end = CivilDate(date.year, month, day)
        if end < date { end = CivilDate(date.year + 1, month, day) }
        let start = CivilDate(end.year - 1, month, day).adding(days: 1)
        return DatePeriod(uncheckedStart: start, end: end)
    }
}
