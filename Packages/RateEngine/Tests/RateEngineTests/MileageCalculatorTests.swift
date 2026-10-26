import Foundation
import XCTest
@testable import RateEngine

final class MileageCalculatorTests: XCTestCase {
    let car = Vehicle(id: "car", vehicleClass: .carOrVan)
    let van = Vehicle(id: "van", vehicleClass: .carOrVan)
    let bike = Vehicle(id: "bike", vehicleClass: .motorcycle)
    var table: RateTable!

    override func setUpWithError() throws {
        table = try RateTable.bundled()
    }

    private var nextID = 0

    private func trip(_ date: CivilDate, _ miles: Decimal, _ vehicle: String = "car",
                      business: Bool = true, confirmed: Bool = true) -> TripRecord {
        nextID += 1
        let id = String(repeating: "0", count: max(0, 4 - String(nextID).count)) + String(nextID)
        return TripRecord(id: "t\(id)", date: date, miles: miles, vehicleID: vehicle,
                          isBusiness: business, isConfirmed: confirmed)
    }

    private func taxYearClaim(_ startYear: Int, _ trips: [TripRecord],
                              scope: ThresholdScope? = nil) throws -> MileageClaim {
        try MileageCalculator.claim(forTaxYear: TaxYear(startYear: startYear), trips: trips,
                                    vehicles: [car, van, bike], table: table, thresholdScope: scope)
    }

    // MARK: Threshold edges, 2026–27 rates (55p / 25p)

    func testJustUnderThreshold() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 9_999)])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5499.45"))
        XCTAssertEqual(claim.figures.first?.carVanMilesAtAfterRate, 0)
    }

    func testExactlyAtThreshold() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 10_000)])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5500.00"))
        XCTAssertEqual(claim.figures.first?.carVanMilesAtFirstRate, 10_000)
        XCTAssertEqual(claim.figures.first?.carVanMilesAtAfterRate, 0)
    }

    func testJustOverThreshold() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 10_001)])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5500.25"))
        XCTAssertEqual(claim.figures.first?.carVanMilesAtAfterRate, 1)
    }

    func testThresholdReachedAcrossManyTrips() throws {
        let trips = (0..<100).map { self.trip(CivilDate(2026, 6, 1 + $0 % 28), Decimal(string: "100.01")!) }
        // 10,001 miles in total: 10,000 at 55p, 1 at 25p.
        let claim = try taxYearClaim(2026, trips)
        XCTAssertEqual(claim.carVanMiles, 10_001)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5500.25"))
    }

    func testPreviousRatesJustOverThreshold() throws {
        let claim = try taxYearClaim(2025, [trip(CivilDate(2025, 5, 1), 10_001)])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "4500.25"))
    }

    // MARK: 5 and 6 April

    func testFifthAprilBelongsToEarlierTaxYear() throws {
        let trips = [trip(CivilDate(2026, 4, 5), 100)]
        XCTAssertEqual(try taxYearClaim(2025, trips).totalPounds, 45)
        XCTAssertEqual(try taxYearClaim(2026, trips).totalPounds, 0)
    }

    func testSixthAprilBelongsToNewTaxYear() throws {
        let trips = [trip(CivilDate(2026, 4, 6), 100)]
        XCTAssertEqual(try taxYearClaim(2025, trips).totalPounds, 0)
        XCTAssertEqual(try taxYearClaim(2026, trips).totalPounds, 55)
    }

    func testTaxYearBoundaries() {
        XCTAssertEqual(TaxYear(containing: CivilDate(2026, 4, 5)), TaxYear(startYear: 2025))
        XCTAssertEqual(TaxYear(containing: CivilDate(2026, 4, 6)), TaxYear(startYear: 2026))
        XCTAssertEqual(TaxYear(containing: CivilDate(2027, 1, 1)), TaxYear(startYear: 2026))
        XCTAssertEqual(TaxYear(startYear: 2026).description, "2026–27")
        XCTAssertEqual(TaxYear(startYear: 2026).period.dayCount, 365)
        XCTAssertEqual(TaxYear(startYear: 2027).period.dayCount, 366) // includes 29 Feb 2028
    }

    // MARK: 31 December year end

    func testThirtyFirstDecemberYearEndApportionsAcrossRateChange() throws {
        let period = try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2026, 12, 31))
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2026, 3, 1), 10_000)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.figures.map(\.taxYear), [TaxYear(startYear: 2025), TaxYear(startYear: 2026)])
        XCTAssertEqual(claim.figures.map(\.overlapDays), [95, 270])
        XCTAssertEqual(claim.figures.map(\.poundsBeforeApportioning), [4500, 5500])
        // 4500 × 95/365 + 5500 × 270/365 = 1171.23… + 4068.49… = 5239.726…
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5239.73"))
        // Rows add up to the total: the last row takes the leftover penny.
        XCTAssertEqual(claim.figures.map(\.apportionedPounds), [Decimal(string: "1171.23")!, Decimal(string: "4068.50")!])
        XCTAssertLessThan(abs(claim.figures.map(\.dayShare).reduce(0, +) - 1), Decimal(string: "1e-30")!)
        XCTAssertTrue(claim.needsRateSplit)
        XCTAssertEqual(claim.apportionmentMethod, .wholePeriodAtEachTaxYearRatesByDays)
    }

    func testYearEndInsideOneRateRegimeNeedsNoSplit() throws {
        let period = try DatePeriod(start: CivilDate(2027, 1, 1), end: CivilDate(2027, 12, 31))
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2027, 3, 1), 12_000)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.figures.count, 2)
        XCTAssertFalse(claim.needsRateSplit)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "6000.00")) // 10,000 × 55p + 2,000 × 25p
    }

    func testTripsOutsidePeriodAreIgnored() throws {
        let period = try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2026, 12, 31))
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2025, 12, 31), 50),
                                                        trip(CivilDate(2027, 1, 1), 50)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.totalPounds, 0)
    }

    func testPeriodLongerThanAYearIsRejected() throws {
        let period = try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2027, 1, 2))
        XCTAssertThrowsError(try MileageCalculator.claim(trips: [], vehicles: [car], period: period, table: table)) {
            XCTAssertEqual($0 as? ClaimError, .periodLongerThanOneYear(days: 367))
        }
    }

    // MARK: Motorcycles

    func testMotorcycleFlatRate() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 12_000, "bike")])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "2880.00"))
    }

    func testMotorcycleMilesDontUseUpCarThreshold() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 5_000, "bike"),
                                            trip(CivilDate(2026, 5, 2), 10_000, "car")])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "6700.00")) // 5,000 × 24p + 10,000 × 55p
    }

    // MARK: Threshold scope

    func testAggregateScopeSharesOneThreshold() throws {
        let trips = [trip(CivilDate(2026, 5, 1), 8_000, "car"), trip(CivilDate(2026, 5, 1), 8_000, "van")]
        let claim = try taxYearClaim(2026, trips, scope: .aggregate)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "7000.00")) // 10,000 × 55p + 6,000 × 25p
    }

    func testPerVehicleScopeGivesEachVehicleAThreshold() throws {
        let trips = [trip(CivilDate(2026, 5, 1), 8_000, "car"), trip(CivilDate(2026, 5, 1), 8_000, "van")]
        let claim = try taxYearClaim(2026, trips, scope: .perVehicle)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "8800.00"))
    }

    func testBundledFileDefaultsToAggregate() {
        XCTAssertEqual(table.thresholdScope, .aggregate)
    }

    // MARK: What counts

    func testSumMilesThenRoundOnce() throws {
        let trips = (1...3).map { self.trip(CivilDate(2026, 5, $0), Decimal(string: "1.005")!) }
        // 3.015 × 55p = £1.65825 → £1.66. Rounding each trip first would give £1.65.
        XCTAssertEqual(try taxYearClaim(2026, trips).totalPounds, Decimal(string: "1.66"))
    }

    func testUnconfirmedAndPersonalTripsNeverCount() throws {
        let trips = [trip(CivilDate(2026, 5, 1), 100, confirmed: false),
                     trip(CivilDate(2026, 5, 1), 100, business: false),
                     trip(CivilDate(2026, 5, 1), 10)]
        XCTAssertEqual(try taxYearClaim(2026, trips).totalPounds, Decimal(string: "5.50"))
    }

    func testVehiclesThatCantUseFlatRatesAreExcluded() throws {
        let actual = Vehicle(id: "actual", vehicleClass: .carOrVan, method: .actualCosts)
        let allowances = Vehicle(id: "ca", vehicleClass: .carOrVan, capitalAllowancesEverClaimed: true)
        let claim = try MileageCalculator.claim(
            forTaxYear: TaxYear(startYear: 2026),
            trips: [trip(CivilDate(2026, 5, 1), 100, "actual"), trip(CivilDate(2026, 5, 1), 100, "ca"),
                    trip(CivilDate(2026, 5, 1), 100, "car")],
            vehicles: [car, actual, allowances], table: table)
        XCTAssertEqual(claim.totalPounds, 55)
        XCTAssertEqual(claim.excludedVehicleIDs, ["actual", "ca"])
        XCTAssertEqual(claim.excludedMilesByVehicle, ["actual": 100, "ca": 100])
    }

    func testUnknownVehicleThrows() {
        XCTAssertThrowsError(try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 1, "ghost")])) {
            XCTAssertEqual($0 as? ClaimError, .unknownVehicle("ghost"))
        }
    }

    func testNegativeMilesThrowsEvenOutsideThePeriod() {
        let bad = trip(CivilDate(2020, 5, 1), -1, confirmed: false)
        XCTAssertThrowsError(try taxYearClaim(2026, [bad])) {
            XCTAssertEqual($0 as? ClaimError, .negativeMiles(tripID: bad.id))
        }
    }

    func testDuplicateVehicleThrows() {
        XCTAssertThrowsError(try MileageCalculator.claim(forTaxYear: TaxYear(startYear: 2026), trips: [],
                                                         vehicles: [car, car], table: table)) {
            XCTAssertEqual($0 as? ClaimError, .duplicateVehicle("car"))
        }
    }

    func testMetresToMiles() {
        XCTAssertEqual(miles(fromMetres: 1609.344), 1)
        XCTAssertEqual(miles(fromMetres: 16093.44), 10)
    }

    // MARK: Added after council round 1

    func testUnconfirmedTripsAreReportedButNotCounted() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 12, confirmed: false),
                                            trip(CivilDate(2026, 5, 2), 8, business: false, confirmed: false),
                                            trip(CivilDate(2025, 5, 2), 99, confirmed: false)])
        XCTAssertEqual(claim.totalPounds, 0)
        XCTAssertEqual(claim.unconfirmedTripCount, 2)
        XCTAssertEqual(claim.unconfirmedMiles, 20)
    }

    func testPerTripAllocationsSplitAtThresholdAndReconcile() throws {
        let trips = [trip(CivilDate(2026, 5, 1), 9_000), trip(CivilDate(2026, 6, 1), 1_500),
                     trip(CivilDate(2026, 7, 1), 100, "bike")]
        let claim = try taxYearClaim(2026, Array(trips.reversed()))
        XCTAssertEqual(claim.trips.map(\.tripID), trips.map(\.id)) // date order
        XCTAssertEqual(claim.trips.map(\.milesAtFirstRate), [9_000, 1_000, 0])
        XCTAssertEqual(claim.trips.map(\.milesAtAfterRate), [0, 500, 0])
        XCTAssertEqual(claim.trips.map(\.pounds), [4950, 675, 24])
        XCTAssertEqual(claim.trips.map(\.pounds).reduce(0, +), claim.totalPounds)
    }

    func testPerTripPenniesAddUpToTotal() throws {
        // Three trips of 1.005 miles: £0.55275 each, £1.66 in total. Floors give £1.65; the
        // leftover penny goes to the earliest trip with the largest remainder.
        let trips = (1...3).map { self.trip(CivilDate(2026, 5, $0), Decimal(string: "1.005")!) }
        let claim = try taxYearClaim(2026, trips)
        XCTAssertEqual(claim.trips.map(\.pounds), [Decimal(string: "0.56")!, Decimal(string: "0.55")!, Decimal(string: "0.55")!])
        XCTAssertEqual(claim.trips.map(\.pounds).reduce(0, +), Decimal(string: "1.66"))
    }

    func testPerTripRowsReconcileAcrossRateSplit() throws {
        let period = try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2026, 12, 31))
        let trips = (1...7).map { self.trip(CivilDate(2026, $0, 3), Decimal(string: "1234.567")!) }
        let claim = try MileageCalculator.claim(trips: trips, vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.trips.map(\.pounds).reduce(0, +), claim.totalPounds)
        XCTAssertEqual(claim.figures.map(\.apportionedPounds).reduce(0, +), claim.totalPounds)
    }

    func testFutureTaxYearIsProvisional() throws {
        XCTAssertFalse(try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 10)]).isProvisional)
        let future = try taxYearClaim(2027, [trip(CivilDate(2027, 5, 1), 10)])
        XCTAssertTrue(future.isProvisional)
        XCTAssertEqual(future.totalPounds, Decimal(string: "5.50"))
    }

    func testAccountingPeriodRunningTotal() throws {
        let yearEnd = try AccountingYearEnd(month: 12, day: 31)
        let claim = try MileageCalculator.claim(forAccountingPeriodContaining: CivilDate(2026, 8, 1), yearEnd: yearEnd,
                                                trips: [trip(CivilDate(2026, 2, 1), 9_000), trip(CivilDate(2026, 9, 1), 2_000)],
                                                vehicles: [car], table: table)
        XCTAssertEqual(claim.period, try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2026, 12, 31)))
        XCTAssertEqual(claim.carVanMiles, 11_000)
        XCTAssertEqual(claim.figures.first?.carVanMilesAtAfterRate, 1_000)
        XCTAssertEqual(claim.milesRemainingAtFirstRate, 0)
    }

    func testTaxYearIsTheDefaultAccountingPeriod() throws {
        let claim = try MileageCalculator.claim(forAccountingPeriodContaining: CivilDate(2026, 4, 5),
                                                trips: [], vehicles: [car], table: table)
        XCTAssertEqual(claim.period, TaxYear(startYear: 2025).period)
    }

    func testMilesRemainingAtFirstRate() throws {
        XCTAssertEqual(try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 2_500)]).milesRemainingAtFirstRate, 7_500)
        XCTAssertNil(try taxYearClaim(2026, [], scope: .perVehicle).milesRemainingAtFirstRate)
    }

    func testLeapYearThirtyFirstDecemberYearEnd() throws {
        let period = try DatePeriod(start: CivilDate(2028, 1, 1), end: CivilDate(2028, 12, 31))
        XCTAssertEqual(period.dayCount, 366)
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2028, 2, 29), 100)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.figures.map(\.overlapDays), [96, 270]) // 1 Jan–5 Apr includes 29 Feb
        XCTAssertEqual(claim.totalPounds, 55)
    }

    func testYearLongPeriodInNonLeapYearCannotRunOneDayOver() throws {
        let period = try DatePeriod(start: CivilDate(2026, 1, 1), end: CivilDate(2027, 1, 1))
        XCTAssertThrowsError(try MileageCalculator.claim(trips: [], vehicles: [car], period: period, table: table)) {
            XCTAssertEqual($0 as? ClaimError, .periodLongerThanOneYear(days: 366))
        }
    }

    func testShortFirstPeriod() throws {
        let period = try DatePeriod(start: CivilDate(2026, 10, 1), end: CivilDate(2027, 4, 5))
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2026, 10, 1), 10_001)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5500.25"))
    }

    func testTripOnLastDayOfPeriodCounts() throws {
        XCTAssertEqual(try taxYearClaim(2026, [trip(CivilDate(2027, 4, 5), 10)]).totalPounds, Decimal(string: "5.50"))
    }

    func testPerVehicleScopeWithMotorcycle() throws {
        let trips = [trip(CivilDate(2026, 5, 1), 11_000, "car"), trip(CivilDate(2026, 5, 1), 3_000, "bike")]
        let claim = try taxYearClaim(2026, trips, scope: .perVehicle)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "6470.00")) // 10,000 × 55p + 1,000 × 25p + 3,000 × 24p
    }

    // MARK: Added after council round 2

    func testThirtyFirstMarchYearEndIsPricedAsTheTaxYear() throws {
        let yearEnd = try AccountingYearEnd(month: 3, day: 31)
        let claim = try MileageCalculator.claim(forAccountingPeriodContaining: CivilDate(2026, 6, 1), yearEnd: yearEnd,
                                                trips: [trip(CivilDate(2026, 4, 2), 10_000)],
                                                vehicles: [car], table: table)
        XCTAssertEqual(claim.period, try DatePeriod(start: CivilDate(2026, 4, 1), end: CivilDate(2027, 3, 31)))
        XCTAssertEqual(claim.figures.map(\.taxYear), [TaxYear(startYear: 2026)])
        XCTAssertEqual(claim.figures.map(\.overlapDays), [365])
        XCTAssertFalse(claim.needsRateSplit)
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5500.00"))
    }

    func testFourthAprilYearEndIsPricedAsTheTaxYear() throws {
        let period = try DatePeriod(start: CivilDate(2025, 4, 5), end: CivilDate(2026, 4, 4))
        let claim = try MileageCalculator.claim(trips: [trip(CivilDate(2025, 4, 5), 100)],
                                                vehicles: [car], period: period, table: table)
        XCTAssertEqual(claim.figures.map(\.taxYear), [TaxYear(startYear: 2025)])
        XCTAssertEqual(claim.totalPounds, 45)
    }

    func testUnknownVehicleOutsidePeriodIsIgnored() throws {
        let claim = try taxYearClaim(2026, [trip(CivilDate(2024, 5, 1), 10, "deleted"),
                                            trip(CivilDate(2026, 5, 1), 10)])
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5.50"))
    }

    func testNonFiniteMilesThrows() {
        let bad = trip(CivilDate(2026, 5, 1), .nan)
        XCTAssertThrowsError(try taxYearClaim(2026, [bad])) {
            XCTAssertEqual($0 as? ClaimError, .invalidMiles(tripID: bad.id))
        }
    }

    func testStoredYearEndIsValidatedOnDecode() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(AccountingYearEnd.self, from: Data(#"{"month":2,"day":29}"#.utf8)))
        let decoded = try JSONDecoder().decode(AccountingYearEnd.self, from: Data(#"{"month":3,"day":31}"#.utf8))
        XCTAssertEqual(decoded, try AccountingYearEnd(month: 3, day: 31))
    }

    func testInvalidYearEnd() {
        XCTAssertThrowsError(try AccountingYearEnd(month: 2, day: 29))
        XCTAssertThrowsError(try AccountingYearEnd(month: 13, day: 1))
    }
}
