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

/// A trip as the engine sees it. Only confirmed business trips are ever counted.
public struct TripRecord: Hashable, Codable, Sendable {
    public let date: CivilDate
    public let miles: Decimal
    public let vehicleID: String
    public let isBusiness: Bool
    public let isConfirmed: Bool

    public init(date: CivilDate, miles: Decimal, vehicleID: String, isBusiness: Bool, isConfirmed: Bool) {
        self.date = date
        self.miles = miles
        self.vehicleID = vehicleID
        self.isBusiness = isBusiness
        self.isConfirmed = isConfirmed
    }
}

/// Miles and money at each rate for one tax year's rates, before apportioning.
public struct BandedFigure: Hashable, Sendable {
    public let taxYear: TaxYear
    public let rates: RateSet
    public let carVanMilesAtFirstRate: Decimal
    public let carVanMilesAtAfterRate: Decimal
    public let motorcycleMiles: Decimal
    /// Unrounded pounds for the whole period's miles at this tax year's rates.
    public let pounds: Decimal
    /// Share of the period's days inside this tax year.
    public let overlapDays: Int
}

public struct MileageClaim: Hashable, Sendable {
    public let period: DatePeriod
    public let thresholdScope: ThresholdScope
    public let rulesVersion: String
    public let carVanMiles: Decimal
    public let motorcycleMiles: Decimal
    /// One entry per tax year the period touches.
    public let figures: [BandedFigure]
    /// The claim in pounds, rounded once to the penny.
    public let totalPounds: Decimal
    /// Vehicles whose business trips were left out because they can't use flat rates.
    public let excludedVehicleIDs: [String]

    /// True when the period crosses tax years with different rates, so the user should see
    /// the plain-English note about the rate split.
    public var needsRateSplit: Bool { Set(figures.map(\.rates)).count > 1 }
}

public enum ClaimError: Error, Equatable {
    case periodEndsBeforeStart
    case periodLongerThanOneYear(days: Int)
    case unknownVehicle(String)
    case negativeMiles
    case noRates(for: TaxYear?)
    case rateSetNotOnTaxYearStart(CivilDate)
    case duplicateRateSet
    case unsupportedSchema(Int)
    case bundledRatesMissing
}

public enum MileageCalculator {
    /// Turns trips into a flat-rate mileage claim for an accounting period.
    ///
    /// Only confirmed business trips dated inside `period`, on vehicles that may use flat
    /// rates, are counted. Miles are summed first and the result is rounded once. Where the
    /// period crosses tax years, the whole period's miles are priced at each tax year's rates
    /// and the results are apportioned by the number of days in each tax year (BIM75005).
    ///
    /// - Parameter thresholdScope: Overrides the scope in `table` when given.
    public static func claim(trips: [TripRecord],
                             vehicles: [Vehicle],
                             period: DatePeriod,
                             table: RateTable,
                             thresholdScope: ThresholdScope? = nil) throws -> MileageClaim {
        // The 10,000-mile threshold is an annual figure.
        guard period.dayCount <= 366 else { throw ClaimError.periodLongerThanOneYear(days: period.dayCount) }
        let scope = thresholdScope ?? table.thresholdScope
        let vehiclesByID = Dictionary(vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var carVanMilesByVehicle: [String: Decimal] = [:]
        var motorcycleMiles: Decimal = 0
        var excluded: Set<String> = []

        for trip in trips where trip.isBusiness && trip.isConfirmed && period.contains(trip.date) {
            guard trip.miles >= 0 else { throw ClaimError.negativeMiles }
            guard let vehicle = vehiclesByID[trip.vehicleID] else { throw ClaimError.unknownVehicle(trip.vehicleID) }
            guard vehicle.canUseFlatRate else {
                excluded.insert(vehicle.id)
                continue
            }
            switch vehicle.vehicleClass {
            case .carOrVan: carVanMilesByVehicle[vehicle.id, default: 0] += trip.miles
            case .motorcycle: motorcycleMiles += trip.miles
            }
        }

        let carVanMiles = carVanMilesByVehicle.values.reduce(0, +)
        let groups: [Decimal] = scope == .aggregate ? [carVanMiles] : Array(carVanMilesByVehicle.values)

        var figures: [BandedFigure] = []
        var unrounded: Decimal = 0
        for taxYear in period.taxYears {
            let rates = try table.rates(for: taxYear)
            let threshold = rates.carVan.thresholdMiles
            var first: Decimal = 0, after: Decimal = 0
            for miles in groups {
                let inFirst = min(miles, threshold)
                first += inFirst
                after += miles - inFirst
            }
            let pence = first * rates.carVan.firstBandPencePerMile
                + after * rates.carVan.afterThresholdPencePerMile
                + motorcycleMiles * rates.motorcyclePencePerMile
            let pounds = pence / 100
            let overlap = period.overlapDays(with: taxYear.period)
            figures.append(BandedFigure(taxYear: taxYear, rates: rates,
                                        carVanMilesAtFirstRate: first, carVanMilesAtAfterRate: after,
                                        motorcycleMiles: motorcycleMiles, pounds: pounds, overlapDays: overlap))
            unrounded += pounds * Decimal(overlap) / Decimal(period.dayCount)
        }

        return MileageClaim(period: period, thresholdScope: scope, rulesVersion: table.rulesVersion,
                            carVanMiles: carVanMiles, motorcycleMiles: motorcycleMiles,
                            figures: figures, totalPounds: roundToPenny(unrounded),
                            excludedVehicleIDs: excluded.sorted())
    }

    /// Running total for a tax year, as shown on the home screen.
    public static func claim(forTaxYear taxYear: TaxYear, trips: [TripRecord], vehicles: [Vehicle],
                             table: RateTable, thresholdScope: ThresholdScope? = nil) throws -> MileageClaim {
        try claim(trips: trips, vehicles: vehicles, period: taxYear.period, table: table,
                  thresholdScope: thresholdScope)
    }

    static func roundToPenny(_ value: Decimal) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}

/// Converts recorded distance to miles without rounding.
public func miles(fromMetres metres: Double) -> Decimal {
    Decimal(metres) / Decimal(string: "1609.344")!
}
