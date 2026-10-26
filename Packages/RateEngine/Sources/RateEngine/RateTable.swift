import Foundation

/// Whether the car/van threshold is counted across all vehicles or for each vehicle on its own.
public enum ThresholdScope: String, Codable, Sendable {
    case aggregate
    case perVehicle
}

/// HMRC flat rates in force from one date until the next set takes over.
public struct RateSet: Codable, Hashable, Sendable {
    public struct CarVan: Codable, Hashable, Sendable {
        public let firstBandPencePerMile: Decimal
        public let thresholdMiles: Decimal
        public let afterThresholdPencePerMile: Decimal

        public init(firstBandPencePerMile: Decimal, thresholdMiles: Decimal, afterThresholdPencePerMile: Decimal) {
            self.firstBandPencePerMile = firstBandPencePerMile
            self.thresholdMiles = thresholdMiles
            self.afterThresholdPencePerMile = afterThresholdPencePerMile
        }
    }

    public let effectiveFrom: CivilDate
    public let carVan: CarVan
    public let motorcyclePencePerMile: Decimal
    public let source: String?
    public let note: String?

    public init(effectiveFrom: CivilDate, carVan: CarVan, motorcyclePencePerMile: Decimal,
                source: String? = nil, note: String? = nil) {
        self.effectiveFrom = effectiveFrom
        self.carVan = carVan
        self.motorcyclePencePerMile = motorcyclePencePerMile
        self.source = source
        self.note = note
    }

    /// True when both sets charge the same amounts, whatever their dates or sources say.
    public func hasSameRates(as other: RateSet) -> Bool {
        carVan == other.carVan && motorcyclePencePerMile == other.motorcyclePencePerMile
    }
}

/// The versioned rates file, decoded.
public struct RateTable: Codable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let rulesVersion: String
    public let thresholdScope: ThresholdScope
    /// Start year of the last tax year whose rates HMRC has published.
    public let ratesConfirmedThroughTaxYear: Int
    public let rateSets: [RateSet]

    public init(rulesVersion: String, thresholdScope: ThresholdScope, ratesConfirmedThroughTaxYear: Int,
                rateSets: [RateSet]) throws {
        self.schemaVersion = Self.supportedSchemaVersion
        self.rulesVersion = rulesVersion
        self.thresholdScope = thresholdScope
        self.ratesConfirmedThroughTaxYear = ratesConfirmedThroughTaxYear
        self.rateSets = rateSets.sorted { $0.effectiveFrom < $1.effectiveFrom }
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        rulesVersion = try c.decode(String.self, forKey: .rulesVersion)
        thresholdScope = try c.decode(ThresholdScope.self, forKey: .thresholdScope)
        ratesConfirmedThroughTaxYear = try c.decode(Int.self, forKey: .ratesConfirmedThroughTaxYear)
        rateSets = try c.decode([RateSet].self, forKey: .rateSets).sorted { $0.effectiveFrom < $1.effectiveFrom }
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, rulesVersion, thresholdScope, ratesConfirmedThroughTaxYear, rateSets
    }

    private func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw ClaimError.unsupportedSchema(schemaVersion)
        }
        guard !rateSets.isEmpty else { throw ClaimError.noRates(for: nil) }
        for set in rateSets {
            // Rates change with the tax year; a mid-year change would break the
            // "each tax year's figure at that year's rates" method.
            guard set.effectiveFrom == TaxYear(containing: set.effectiveFrom).firstDay else {
                throw ClaimError.rateSetNotOnTaxYearStart(set.effectiveFrom)
            }
        }
        guard Set(rateSets.map(\.effectiveFrom)).count == rateSets.count else {
            throw ClaimError.duplicateRateSet
        }
        // Per-trip band splits assume one threshold for every tax year.
        guard Set(rateSets.map(\.carVan.thresholdMiles)).count == 1 else {
            throw ClaimError.thresholdChangesBetweenRateSets
        }
    }

    /// The rates for a tax year: the latest set that started on or before its first day.
    public func rates(for taxYear: TaxYear) throws -> RateSet {
        guard let set = rateSets.last(where: { $0.effectiveFrom <= taxYear.firstDay }) else {
            throw ClaimError.noRates(for: taxYear)
        }
        return set
    }

    /// True when HMRC hasn't published rates for `taxYear` yet, so the latest known rates stand in.
    public func isProvisional(_ taxYear: TaxYear) -> Bool {
        taxYear.startYear > ratesConfirmedThroughTaxYear
    }

    /// The rates file shipped with the package.
    public static func bundled() throws -> RateTable {
        guard let url = Bundle.module.url(forResource: "rates", withExtension: "json") else {
            throw ClaimError.bundledRatesMissing
        }
        return try load(from: Data(contentsOf: url))
    }

    public static func load(from data: Data) throws -> RateTable {
        try JSONDecoder().decode(RateTable.self, from: data)
    }
}
