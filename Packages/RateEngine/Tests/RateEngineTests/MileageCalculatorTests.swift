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

    private func trip(_ date: CivilDate, _ miles: Decimal, _ vehicle: String = "car",
                      business: Bool = true, confirmed: Bool = true) -> TripRecord {
        TripRecord(date: date, miles: miles, vehicleID: vehicle, isBusiness: business, isConfirmed: confirmed)
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
        let trips = (0..<100).map { trip(CivilDate(2026, 6, 1 + $0 % 28), Decimal(string: "100.01")!) }
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
        XCTAssertEqual(claim.figures.map(\.pounds), [4500, 5500])
        // 4500 × 95/365 + 5500 × 270/365 = 5239.726…
        XCTAssertEqual(claim.totalPounds, Decimal(string: "5239.73"))
        XCTAssertTrue(claim.needsRateSplit)
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
        let trips = (1...3).map { trip(CivilDate(2026, 5, $0), Decimal(string: "1.005")!) }
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
    }

    func testUnknownVehicleThrows() {
        XCTAssertThrowsError(try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), 1, "ghost")])) {
            XCTAssertEqual($0 as? ClaimError, .unknownVehicle("ghost"))
        }
    }

    func testNegativeMilesThrows() {
        XCTAssertThrowsError(try taxYearClaim(2026, [trip(CivilDate(2026, 5, 1), -1)])) {
            XCTAssertEqual($0 as? ClaimError, .negativeMiles)
        }
    }

    func testMetresToMiles() {
        XCTAssertEqual(miles(fromMetres: 1609.344), 1)
    }
}
