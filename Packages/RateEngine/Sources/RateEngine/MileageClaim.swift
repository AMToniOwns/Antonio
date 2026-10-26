import Foundation

public enum VehicleClass: String, Codable, Sendable {
    case carOrVan
    case motorcycle
}

/// The expense method a vehicle uses. Only `.flatRate` vehicles can claim mileage.
public enum ExpenseMethod: String, Codable, Sendable {
    case flatRate
    case actualCosts
}

public struct Vehicle: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let vehicleClass: VehicleClass
    public let method: ExpenseMethod
    /// Flat rates aren't available for a vehicle that has ever had capital allowances claimed on it.
    public let capitalAllowancesEverClaimed: Bool

    public init(id: String, vehicleClass: VehicleClass, method: ExpenseMethod = .flatRate,
                capitalAllowancesEverClaimed: Bool = false) {
        self.id = id
        self.vehicleClass = vehicleClass
        self.method = method
        self.capitalAllowancesEverClaimed = capitalAllowancesEverClaimed
    }

    public var canUseFlatRate: Bool { method == .flatRate && !capitalAllowancesEverClaimed }
}

/// Where a trip came from, so exports and audits can say how each line was recorded.
public enum TripSource: String, Codable, Sendable {
    case detected
    case recovered
    case manual
}

/// A trip as the engine sees it. Only confirmed business trips are ever counted.
public struct TripRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    /// The Europe/London date the trip started on. A trip over midnight on 5/6 April belongs to
    /// the day it started.
    public let date: CivilDate
    public let miles: Decimal
    public let vehicleID: String
    public let isBusiness: Bool
    public let isConfirmed: Bool
    public let source: TripSource

    public init(id: String, date: CivilDate, miles: Decimal, vehicleID: String, isBusiness: Bool,
                isConfirmed: Bool, source: TripSource = .detected) {
        self.id = id
        self.date = date
        self.miles = miles
        self.vehicleID = vehicleID
        self.isBusiness = isBusiness
        self.isConfirmed = isConfirmed
        self.source = source
    }
}

/// How a period that crosses tax years is priced.
public enum ApportionmentMethod: String, Codable, Sendable {
    /// The whole period's miles are priced at each tax year's rates, and each result is weighted
    /// by the share of the period's days in that tax year (BIM75005). Pending accountant sign-off.
    case wholePeriodAtEachTaxYearRatesByDays

    public var explanation: String {
        switch self {
        case .wholePeriodAtEachTaxYearRatesByDays:
            return "Your accounting year spans more than one tax year, so all its business miles are priced "
                + "at each tax year's rates and the results are shared out by the number of days in each tax year."
        }
    }
}

/// The period's miles priced at one tax year's rates.
public struct BandedFigure: Hashable, Sendable {
    public let taxYear: TaxYear
    public let rates: RateSet
    /// True when HMRC hasn't published rates for this tax year and the latest known rates stand in.
    public let ratesAreProvisional: Bool
    public let carVanMilesAtFirstRate: Decimal
    public let carVanMilesAtAfterRate: Decimal
    public let motorcycleMiles: Decimal
    /// Unrounded pounds for the whole period's miles at this tax year's rates.
    public let poundsBeforeApportioning: Decimal
    /// Days of the period inside this tax year.
    public let overlapDays: Int
    /// `overlapDays` divided by the period's length.
    public let dayShare: Decimal
    /// This tax year's share of the claim, to the penny. The rows add up exactly to the claim
    /// total: each is rounded, and the last row takes any penny left over.
    public let apportionedPounds: Decimal
}

/// One counted trip's share of the claim, for per-trip exports.
public struct TripAllocation: Hashable, Sendable {
    public let tripID: String
    public let date: CivilDate
    public let vehicleID: String
    public let source: TripSource
    public let milesAtFirstRate: Decimal
    public let milesAtAfterRate: Decimal
    public let motorcycleMiles: Decimal
    /// Unrounded pounds.
    public let exactPounds: Decimal
    /// Pounds to the penny. Allocations add up exactly to the claim total; leftover pennies go to
    /// the trips with the largest rounding remainders, earliest first.
    public let pounds: Decimal
}

public struct MileageClaim: Hashable, Sendable {
    public let period: DatePeriod
    public let thresholdScope: ThresholdScope
    public let apportionmentMethod: ApportionmentMethod
    public let rulesVersion: String
    public let carVanMiles: Decimal
    public let motorcycleMiles: Decimal
    /// One entry per tax year the period touches, earliest first.
    public let figures: [BandedFigure]
    /// Counted trips in date order.
    public let trips: [TripAllocation]
    /// The claim in pounds, rounded once to the penny.
    public let totalPounds: Decimal
    /// Trips in the period that the user hasn't confirmed yet. They aren't counted.
    public let unconfirmedTripCount: Int
    public let unconfirmedMiles: Decimal
    /// Confirmed business miles left out because the vehicle can't use flat rates.
    public let excludedMilesByVehicle: [String: Decimal]

    public var excludedVehicleIDs: [String] { excludedMilesByVehicle.keys.sorted() }

    /// True when any part of the claim uses rates HMRC hasn't published yet.
    public var isProvisional: Bool { figures.contains { $0.ratesAreProvisional } }

    /// True when the period crosses tax years with different rates, so the user should see
    /// `apportionmentMethod.explanation`.
    public var needsRateSplit: Bool {
        guard let first = figures.first?.rates else { return false }
        return figures.contains { !$0.rates.hasSameRates(as: first) }
    }

    /// Car and van miles still available at the first-band rate (aggregate scope only).
    public var milesRemainingAtFirstRate: Decimal? {
        guard thresholdScope == .aggregate, let threshold = figures.last?.rates.carVan.thresholdMiles else { return nil }
        return max(0, threshold - carVanMiles)
    }
}

public enum ClaimError: Error, Equatable {
    case periodEndsBeforeStart
    case periodLongerThanOneYear(days: Int)
    case invalidYearEnd
    case unknownVehicle(String)
    case duplicateVehicle(String)
    case negativeMiles(tripID: String)
    case noRates(for: TaxYear?)
    case rateSetNotOnTaxYearStart(CivilDate)
    case duplicateRateSet
    case thresholdChangesBetweenRateSets
    case unsupportedSchema(Int)
    case bundledRatesMissing
}

public enum MileageCalculator {
    /// Turns trips into a flat-rate mileage claim for an accounting period of up to a year.
    ///
    /// Only confirmed business trips dated inside `period`, on vehicles that may use flat
    /// rates, are counted. Miles are summed first and the result is rounded once. Where the
    /// period crosses tax years, see `ApportionmentMethod.wholePeriodAtEachTaxYearRatesByDays`.
    ///
    /// - Parameter thresholdScope: Overrides the scope in `table` when given.
    public static func claim(trips: [TripRecord],
                             vehicles: [Vehicle],
                             period: DatePeriod,
                             table: RateTable,
                             thresholdScope: ThresholdScope? = nil) throws -> MileageClaim {
        // The 10,000-mile threshold is an annual figure.
        guard period.end < period.start.oneYearLater else {
            throw ClaimError.periodLongerThanOneYear(days: period.dayCount)
        }
        let scope = thresholdScope ?? table.thresholdScope
        var vehiclesByID: [String: Vehicle] = [:]
        for vehicle in vehicles {
            guard vehiclesByID.updateValue(vehicle, forKey: vehicle.id) == nil else {
                throw ClaimError.duplicateVehicle(vehicle.id)
            }
        }

        var counted: [(trip: TripRecord, vehicle: Vehicle)] = []
        var unconfirmedCount = 0
        var unconfirmedMiles: Decimal = 0
        var excluded: [String: Decimal] = [:]

        for trip in trips {
            guard trip.miles >= 0 else { throw ClaimError.negativeMiles(tripID: trip.id) }
            guard let vehicle = vehiclesByID[trip.vehicleID] else { throw ClaimError.unknownVehicle(trip.vehicleID) }
            guard period.contains(trip.date) else { continue }
            if !trip.isConfirmed {
                unconfirmedCount += 1
                unconfirmedMiles += trip.miles
                continue
            }
            guard trip.isBusiness else { continue }
            guard vehicle.canUseFlatRate else {
                excluded[vehicle.id, default: 0] += trip.miles
                continue
            }
            counted.append((trip, vehicle))
        }
        counted.sort { ($0.trip.date, $0.trip.id) < ($1.trip.date, $1.trip.id) }

        let taxYears = period.taxYears
        let yearRates = try taxYears.map { try table.rates(for: $0) }
        // validate() guarantees every set has the same threshold.
        let threshold = yearRates[0].carVan.thresholdMiles

        // Split each trip's miles into bands, in date order.
        var usedByGroup: [String: Decimal] = [:]
        var splits: [(first: Decimal, after: Decimal, motorcycle: Decimal)] = []
        for (trip, vehicle) in counted {
            switch vehicle.vehicleClass {
            case .motorcycle:
                splits.append((0, 0, trip.miles))
            case .carOrVan:
                let group = scope == .aggregate ? "" : vehicle.id
                let used = usedByGroup[group, default: 0]
                let first = min(trip.miles, max(0, threshold - used))
                usedByGroup[group] = used + trip.miles
                splits.append((first, trip.miles - first, 0))
            }
        }
        let first = splits.reduce(0) { $0 + $1.first }
        let after = splits.reduce(0) { $0 + $1.after }
        let motorcycle = splits.reduce(0) { $0 + $1.motorcycle }

        // Pence × days for each mile type, summed over tax years; divided once at the end.
        let days = taxYears.map { Decimal(period.overlapDays(with: $0.period)) }
        let divisor = Decimal(100 * period.dayCount)
        func weightedPence(_ f: Decimal, _ a: Decimal, _ m: Decimal) -> Decimal {
            zip(yearRates, days).reduce(0) { sum, pair in
                let (rates, d) = pair
                return sum + (f * rates.carVan.firstBandPencePerMile
                    + a * rates.carVan.afterThresholdPencePerMile
                    + m * rates.motorcyclePencePerMile) * d
            }
        }
        let exactTotal = weightedPence(first, after, motorcycle) / divisor
        let total = roundToPenny(exactTotal, .plain)

        // Per-year rows.
        var figures: [BandedFigure] = []
        var rowsSoFar: Decimal = 0
        for (index, (taxYear, rates)) in zip(taxYears, yearRates).enumerated() {
            let pence = first * rates.carVan.firstBandPencePerMile
                + after * rates.carVan.afterThresholdPencePerMile
                + motorcycle * rates.motorcyclePencePerMile
            let overlap = period.overlapDays(with: taxYear.period)
            let isLast = index == taxYears.count - 1
            let row = isLast ? total - rowsSoFar : roundToPenny(pence * Decimal(overlap) / divisor, .plain)
            rowsSoFar += row
            figures.append(BandedFigure(taxYear: taxYear, rates: rates,
                                        ratesAreProvisional: table.isProvisional(taxYear),
                                        carVanMilesAtFirstRate: first, carVanMilesAtAfterRate: after,
                                        motorcycleMiles: motorcycle, poundsBeforeApportioning: pence / 100,
                                        overlapDays: overlap,
                                        dayShare: Decimal(overlap) / Decimal(period.dayCount),
                                        apportionedPounds: row))
        }

        // Per-trip rows, reconciled to the total by largest remainder.
        let exact = splits.map { weightedPence($0.first, $0.after, $0.motorcycle) / divisor }
        var pounds = exact.map { roundToPenny($0, .down) }
        var leftoverPennies = NSDecimalNumber(decimal: (total - pounds.reduce(0, +)) * 100).intValue
        let byRemainder = exact.indices.sorted {
            let (a, b) = (exact[$0] - pounds[$0], exact[$1] - pounds[$1])
            return a != b ? a > b : $0 < $1
        }
        for index in byRemainder where leftoverPennies > 0 {
            pounds[index] += Decimal(string: "0.01")!
            leftoverPennies -= 1
        }
        let allocations = counted.indices.map { i in
            TripAllocation(tripID: counted[i].trip.id, date: counted[i].trip.date,
                           vehicleID: counted[i].vehicle.id, source: counted[i].trip.source,
                           milesAtFirstRate: splits[i].first, milesAtAfterRate: splits[i].after,
                           motorcycleMiles: splits[i].motorcycle, exactPounds: exact[i], pounds: pounds[i])
        }

        return MileageClaim(period: period, thresholdScope: scope,
                            apportionmentMethod: .wholePeriodAtEachTaxYearRatesByDays,
                            rulesVersion: table.rulesVersion,
                            carVanMiles: first + after, motorcycleMiles: motorcycle,
                            figures: figures, trips: allocations, totalPounds: total,
                            unconfirmedTripCount: unconfirmedCount, unconfirmedMiles: unconfirmedMiles,
                            excludedMilesByVehicle: excluded)
    }

    /// Running total for the accounting period containing `date`, as shown on the home screen.
    public static func claim(forAccountingPeriodContaining date: CivilDate,
                             yearEnd: AccountingYearEnd = .taxYear,
                             trips: [TripRecord], vehicles: [Vehicle], table: RateTable,
                             thresholdScope: ThresholdScope? = nil) throws -> MileageClaim {
        try claim(trips: trips, vehicles: vehicles, period: yearEnd.period(containing: date), table: table,
                  thresholdScope: thresholdScope)
    }

    /// Claim for a whole tax year.
    public static func claim(forTaxYear taxYear: TaxYear, trips: [TripRecord], vehicles: [Vehicle],
                             table: RateTable, thresholdScope: ThresholdScope? = nil) throws -> MileageClaim {
        try claim(trips: trips, vehicles: vehicles, period: taxYear.period, table: table,
                  thresholdScope: thresholdScope)
    }

    static func roundToPenny(_ value: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, 2, mode)
        return result
    }
}

/// Converts recorded distance to miles without rounding.
///
/// Goes through the shortest decimal text for `metres`, so a reading like 1609.344 stays exactly
/// that instead of picking up binary noise from `Double`.
public func miles(fromMetres metres: Double) -> Decimal {
    (Decimal(string: String(metres)) ?? Decimal(metres)) / Decimal(string: "1609.344")!
}
