import Foundation
import Testing
@testable import TokenTankKit

struct ModelsTests {
    @Test func scopeRawValuesAreStable() {
        #expect(Scope.account.rawValue == "account")
        #expect(Scope.quota("mimo.tokenplan").rawValue == "quota:mimo.tokenplan")
        #expect(Scope(rawValue: "account") == .account)
        #expect(Scope(rawValue: "quota:mimo.tokenplan") == .quota("mimo.tokenplan"))
        #expect(Scope(rawValue: "bogus") == nil)
    }

    @Test func scopeEncodesRawString() throws {
        let data = try JSONEncoder().encode(Scope.quota("mimo.tokenplan"))
        #expect(String(data: data, encoding: .utf8) == "\"quota:mimo.tokenplan\"")
        let decoded = try JSONDecoder().decode(Scope.self, from: Data("\"account\"".utf8))
        #expect(decoded == .account)
    }

    @Test func thresholdValidatesTargets() throws {
        let money = try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 10, rearmFraction: 1.1)
        #expect(money.currency == "CNY")
        let quota = try Threshold(currency: nil, unit: .credits, quotaID: "mimo.tokenplan", value: 100, rearmFraction: 1.1)
        #expect(quota.quotaID == "mimo.tokenplan")
        #expect(throws: ThresholdError.conflictingTarget) {
            try Threshold(currency: "CNY", unit: .credits, quotaID: "q", value: 1, rearmFraction: 1)
        }
        #expect(throws: ThresholdError.conflictingTarget) {
            try Threshold(currency: nil, unit: nil, quotaID: nil, value: 1, rearmFraction: 1)
        }
        #expect(throws: ThresholdError.quotaIDMismatch) {
            try Threshold(currency: nil, unit: .credits, quotaID: nil, value: 1, rearmFraction: 1)
        }
        #expect(throws: ThresholdError.quotaIDMismatch) {
            try Threshold(currency: "CNY", unit: nil, quotaID: "q", value: 1, rearmFraction: 1)
        }
    }

    @Test func thresholdValidatesValueRearmAndCurrency() {
        #expect(throws: ThresholdError.nonPositiveValue) {
            try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 0, rearmFraction: 1.1)
        }
        #expect(throws: ThresholdError.invalidRearm) {
            try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 10, rearmFraction: 0.5)
        }
        #expect(throws: ThresholdError.unknownCurrency) {
            try Threshold(currency: "RMB", unit: nil, quotaID: nil, value: 10, rearmFraction: 1.1)
        }
        #expect(throws: ThresholdError.emptyQuotaID) {
            try Threshold(currency: nil, unit: .credits, quotaID: "", value: 10, rearmFraction: 1.1)
        }
    }

    @Test func thresholdDecodingToleratesUnvalidatedLegacyValues() throws {
        // Data written before validation existed must keep decoding: the account
        // store drops records, not fields (§4).
        let json = #"{"currency": "CNY", "value": 10, "rearmFraction": 0.5}"#
        let decoded = try JSONDecoder().decode(Threshold.self, from: Data(json.utf8))
        #expect(decoded.rearmFraction == 0.5)
    }

    @Test func thresholdCodableRoundTrip() throws {
        let threshold = try Threshold(currency: "USD", unit: nil, quotaID: nil, value: 2.5, rearmFraction: 1.2)
        let decoded = try JSONDecoder().decode(Threshold.self, from: JSONEncoder().encode(threshold))
        #expect(decoded.currency == threshold.currency)
        #expect(decoded.value == threshold.value)
        #expect(decoded.rearmFraction == threshold.rearmFraction)
    }

    @Test func providerErrorCodableRoundTrip() throws {
        let cases: [ProviderError] = [
            .invalidKey,
            .regionMismatch,
            .rateLimited(retryAfter: 30),
            .rateLimited(retryAfter: nil),
            .server(status: 502),
            .network(code: -1009),
            .decoding,
            .dataNotReady,
            .unsupported,
        ]
        for error in cases {
            let decoded = try JSONDecoder().decode(ProviderError.self, from: JSONEncoder().encode(error))
            #expect(decoded == error)
        }
    }

    @Test func fetchStatusCodableRoundTrip() throws {
        let cases: [FetchStatus] = [.ok, .failed(.invalidKey), .failed(.rateLimited(retryAfter: 5)), .unsupported]
        for status in cases {
            let decoded = try JSONDecoder().decode(FetchStatus.self, from: JSONEncoder().encode(status))
            #expect(decoded == status)
        }
    }

    @Test func rateLimitsFromResponseHeaders() {
        let headers = ["X-RateLimit-Limit": "100", "X-RateLimit-Remaining": "42", "X-RateLimit-Reset": "1794528000"]
        let limits = RateLimits.fromResponseHeaders(headers)
        #expect(limits?.source == .responseHeaders)
        #expect(limits?.rpm?.value == 100)
        #expect(limits?.rpm?.resetsAt == Date(timeIntervalSince1970: 1_794_528_000))
        #expect(RateLimits.fromResponseHeaders(["X-RateLimit-Remaining": "1"]) == nil)
    }

    @Test func tierTableBuildsLimits() throws {
        let table = TierTable(tiers: [
            TierTable.Tier(id: "Tier0", rpm: 3, tpm: 500_000, tpd: 1_500_000),
            TierTable.Tier(id: "Tier1", rpm: 100, tpm: 2_000_000, tpd: nil),
        ])
        let limits = table.rateLimits(for: "Tier1")
        #expect(limits?.source == .tierTable)
        #expect(limits?.tier == "Tier1")
        #expect(limits?.rpm?.value == 100)
        #expect(limits?.tpd == nil)
        #expect(table.rateLimits(for: "Tier0")?.tpd?.value == 1_500_000)
        #expect(table.rateLimits(for: nil) == nil)
        #expect(table.rateLimits(for: "Tier9") == nil)
    }
}
