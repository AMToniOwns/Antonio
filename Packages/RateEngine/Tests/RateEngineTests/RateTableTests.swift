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
    }

    func testNoRatesBeforeFirstSet() throws {
        let table = try RateTable.bundled()
        XCTAssertThrowsError(try table.rates(for: TaxYear(startYear: 2010))) {
            XCTAssertEqual($0 as? ClaimError, .noRates(for: TaxYear(startYear: 2010)))
        }
    }

    func testRejectsRateSetNotStartingOnSixthApril() {
        let json = """
        {"schemaVersion":1,"rulesVersion":"x","thresholdScope":"aggregate","rateSets":[
          {"effectiveFrom":"2026-04-01","carVan":{"firstBandPencePerMile":55,"thresholdMiles":10000,
           "afterThresholdPencePerMile":25},"motorcyclePencePerMile":24}]}
        """
        XCTAssertThrowsError(try RateTable.load(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? ClaimError, .rateSetNotOnTaxYearStart(CivilDate(2026, 4, 1)))
        }
    }

    func testRejectsUnknownSchema() {
        let json = #"{"schemaVersion":2,"rulesVersion":"x","thresholdScope":"aggregate","rateSets":[]}"#
        XCTAssertThrowsError(try RateTable.load(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? ClaimError, .unsupportedSchema(2))
        }
    }

    func testCivilDateParsing() {
        XCTAssertEqual(CivilDate(iso: "2028-02-29"), CivilDate(2028, 2, 29))
        XCTAssertNil(CivilDate(iso: "2027-02-29"))
        XCTAssertNil(CivilDate(iso: "2026-13-01"))
        XCTAssertEqual(CivilDate(1970, 1, 1).dayNumber, 0)
        XCTAssertEqual(CivilDate(2026, 4, 6).description, "2026-04-06")
    }
}
