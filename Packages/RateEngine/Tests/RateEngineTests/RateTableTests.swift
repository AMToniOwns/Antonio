import Foundation
import XCTest
@testable import RateEngine

final class RateTableTests: XCTestCase {
    func testBundledRates() throws {
        let table = try RateTable.bundled()
        let old = try table.rates(for: TaxYear(startYear: 2025))
        let new = try table.rates(for: TaxYear(startYear: 2026))
        XCTAssertEqual(old.carVan.firstBandPencePerMile, 45)
        XCTAssertEqual(new.carVan.firstBandPencePerMile, 55)
        XCTAssertEqual(new.carVan.afterThresholdPencePerMile, 25)
        XCTAssertEqual(new.carVan.thresholdMiles, 10_000)
        XCTAssertEqual(new.motorcyclePencePerMile, 24)
        // Future years keep the latest rates until the file is updated.
        XCTAssertEqual(try table.rates(for: TaxYear(startYear: 2030)), new)
        XCTAssertTrue(table.isProvisional(TaxYear(startYear: 2027)))
        XCTAssertFalse(table.isProvisional(TaxYear(startYear: 2026)))
        // Simplified expenses start in 2013–14.
        XCTAssertEqual(try table.rates(for: TaxYear(startYear: 2013)), old)
    }

    func testSameRatesIgnoresSourceAndDate() {
        let rates = RateSet.CarVan(firstBandPencePerMile: 55, thresholdMiles: 10_000, afterThresholdPencePerMile: 25)
        let a = RateSet(effectiveFrom: CivilDate(2026, 4, 6), carVan: rates, motorcyclePencePerMile: 24, source: "a")
        let b = RateSet(effectiveFrom: CivilDate(2027, 4, 6), carVan: rates, motorcyclePencePerMile: 24, source: "b")
        XCTAssertTrue(a.hasSameRates(as: b))
    }

    func testRejectsThresholdChange() {
        let a = RateSet(effectiveFrom: CivilDate(2026, 4, 6),
                        carVan: .init(firstBandPencePerMile: 55, thresholdMiles: 10_000, afterThresholdPencePerMile: 25),
                        motorcyclePencePerMile: 24)
        let b = RateSet(effectiveFrom: CivilDate(2027, 4, 6),
                        carVan: .init(firstBandPencePerMile: 55, thresholdMiles: 12_000, afterThresholdPencePerMile: 25),
                        motorcyclePencePerMile: 24)
        XCTAssertThrowsError(try RateTable(rulesVersion: "x", thresholdScope: .aggregate,
                                           ratesConfirmedThroughTaxYear: 2027, rateSets: [a, b])) {
            XCTAssertEqual($0 as? ClaimError, .thresholdChangesBetweenRateSets)
        }
    }

    func testNoRatesBeforeFirstSet() throws {
        let table = try RateTable.bundled()
        XCTAssertThrowsError(try table.rates(for: TaxYear(startYear: 2012))) {
            XCTAssertEqual($0 as? ClaimError, .noRates(for: TaxYear(startYear: 2012)))
        }
    }

    func testRejectsRateSetNotStartingOnSixthApril() {
        let json = """
        {"schemaVersion":1,"rulesVersion":"x","thresholdScope":"aggregate","ratesConfirmedThroughTaxYear":2026,"rateSets":[
          {"effectiveFrom":"2026-04-01","carVan":{"firstBandPencePerMile":55,"thresholdMiles":10000,
           "afterThresholdPencePerMile":25},"motorcyclePencePerMile":24}]}
        """
        XCTAssertThrowsError(try RateTable.load(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? ClaimError, .rateSetNotOnTaxYearStart(CivilDate(2026, 4, 1)))
        }
    }

    func testRejectsUnknownSchema() {
        let json = #"{"schemaVersion":2,"rulesVersion":"x","thresholdScope":"aggregate","ratesConfirmedThroughTaxYear":2026,"rateSets":[]}"#
        XCTAssertThrowsError(try RateTable.load(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? ClaimError, .unsupportedSchema(2))
        }
    }

    func testCivilDateParsing() {
        XCTAssertEqual(CivilDate(iso: "2028-02-29"), CivilDate(2028, 2, 29))
        XCTAssertNil(CivilDate(iso: "2027-02-29"))
        XCTAssertNil(CivilDate(iso: "2026-13-01"))
        XCTAssertNil(CivilDate(iso: "2026-4-6"))
        XCTAssertEqual(CivilDate(dayNumber: CivilDate(2028, 2, 29).dayNumber), CivilDate(2028, 2, 29))
        XCTAssertEqual(CivilDate(2026, 12, 31).adding(days: 1), CivilDate(2027, 1, 1))
        XCTAssertEqual(CivilDate(2028, 2, 29).oneYearLater, CivilDate(2029, 3, 1))
        XCTAssertEqual(CivilDate(1970, 1, 1).dayNumber, 0)
        XCTAssertEqual(CivilDate(2026, 4, 6).description, "2026-04-06")
    }
}
