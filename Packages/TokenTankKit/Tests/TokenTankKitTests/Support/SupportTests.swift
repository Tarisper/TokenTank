import Foundation
import Testing
@testable import TokenTankKit

struct SupportTests {
    @Test func keyMaskKeepsPrefixAndLastFour() {
        #expect(KeyMask.format("sk-abcdef1234567890") == "sk-…7890")
        #expect(KeyMask.format("sk-admin-secret-1") == "sk-…et-1")
        #expect(KeyMask.format("nodash") == "…")
        #expect(KeyMask.format("sk-12345") == "…")
    }

    @Test func urlRouterParsesDeepLinks() {
        #expect(URLRouter.route(for: URL(string: "tokentank://add")!) == .add)
        #expect(URLRouter.route(for: URL(string: "tokentank://account/6F1E4B2C-8A44-4A0B-9E67-1B7A3F0D2C11")!) == .account(UUID(uuidString: "6F1E4B2C-8A44-4A0B-9E67-1B7A3F0D2C11")!))
        #expect(URLRouter.route(for: URL(string: "tokentank://account/not-a-uuid")!) == nil)
        #expect(URLRouter.route(for: URL(string: "tokentank://bogus")!) == nil)
        #expect(URLRouter.route(for: URL(string: "https://example.com/add")!) == nil)
    }

    @Test func baseURLPolicySplitsAllowlistAndGateway() {
        #expect(BaseURLPolicy.validate(URL(string: "https://api.deepseek.com")!, provider: .deepseek, region: nil) == .allowed)
        #expect(BaseURLPolicy.validate(URL(string: "https://token-plan-cn.xiaomimimo.com")!, provider: .mimo, region: nil) == .allowed)
        #expect(BaseURLPolicy.validate(URL(string: "https://api.moonshot.cn")!, provider: .kimi, region: .cn) == .allowed)
        #expect(BaseURLPolicy.validate(URL(string: "https://api.moonshot.cn")!, provider: .kimi, region: .intl) == .customGateway)
        #expect(BaseURLPolicy.validate(URL(string: "https://api.kimi.com")!, provider: .kimi, region: .cn) == .allowed)
        #expect(BaseURLPolicy.validate(URL(string: "https://api.kimi.com")!, provider: .kimi, region: .intl) == .allowed)
        #expect(BaseURLPolicy.validate(URL(string: "https://gateway.example.com")!, provider: .mimo, region: nil) == .customGateway)
        #expect(BaseURLPolicy.validate(URL(string: "http://api.deepseek.com")!, provider: .deepseek, region: nil) == .invalid)
    }
}
