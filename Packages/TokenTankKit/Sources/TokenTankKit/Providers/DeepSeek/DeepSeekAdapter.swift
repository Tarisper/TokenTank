import Foundation

/// DeepSeek adapter: only the balance is exposed (`GET /user/balance`);
/// quotas, usage and limits are `unsupported`.
public struct DeepSeekAdapter: BalanceProvider {
    public let descriptor: AccountDescriptor
    private let keychain: KeychainClient
    private let http: HTTPClient

    /// - Parameters:
    ///   - descriptor: Account settings.
    ///   - keychain: Source of the API key.
    ///   - http: HTTP client.
    public init(descriptor: AccountDescriptor, keychain: KeychainClient, http: HTTPClient = HTTPClient()) {
        self.descriptor = descriptor
        self.keychain = keychain
        self.http = http
    }

    public func fetchPrimary(scope: Scope) async -> Result<PrimarySnapshot, ProviderError> {
        let result: Result<PrimarySnapshot, ProviderError>
        do {
            switch scope {
            case .account:
                let balance = try await fetchBalance(timeout: 3)
                result = .success(PrimarySnapshot(scope: scope, fetchedAt: Date(), balances: balance.balances, quota: nil))
            case .quota:
                result = .failure(.unsupported)
            }
        } catch let error as ProviderError {
            result = .failure(error)
        } catch {
            result = .failure(.network(code: URLError.Code.unknown.rawValue))
        }
        return result
    }

    public func fetchAccount() async throws -> AccountSnapshot {
        let now = Date()
        var balances: [Money]?
        var isAvailable: Bool?
        var balanceSection = SectionSnapshot(kind: .balance, slotID: "sk", status: .unsupported, lastSuccessAt: nil, lastAttemptAt: now)
        do {
            let balance = try await fetchBalance(timeout: 10)
            balances = balance.balances
            isAvailable = balance.isAvailable
            balanceSection = SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: now, lastAttemptAt: now)
        } catch let error as ProviderError {
            balanceSection = SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now)
        }
        return AccountSnapshot(
            accountID: descriptor.id,
            updatedAt: now,
            isAvailable: isAvailable,
            balances: balances,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [
                balanceSection,
                SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
                SectionSnapshot(kind: .usage, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
                SectionSnapshot(kind: .limits, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
            ]
        )
    }

    private func fetchBalance(timeout: TimeInterval) async throws -> (balances: [Money], isAvailable: Bool?) {
        struct BalanceResponse: Decodable {
            struct BalanceInfo: Decodable {
                let currency: String?
                let totalBalance: Decimal?
                let grantedBalance: Decimal?
                let toppedUpBalance: Decimal?

                enum CodingKeys: String, CodingKey {
                    case currency
                    case totalBalance = "total_balance"
                    case grantedBalance = "granted_balance"
                    case toppedUpBalance = "topped_up_balance"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    currency = try container.decodeIfPresent(String.self, forKey: .currency)
                    totalBalance = try container.decodeDecimalIfPresent(forKey: .totalBalance)
                    grantedBalance = try container.decodeDecimalIfPresent(forKey: .grantedBalance)
                    toppedUpBalance = try container.decodeDecimalIfPresent(forKey: .toppedUpBalance)
                }
            }

            let isAvailable: Bool?
            let balanceInfos: [BalanceInfo]

            enum CodingKeys: String, CodingKey {
                case isAvailable = "is_available"
                case balanceInfos = "balance_infos"
            }
        }

        guard let base = AdapterRegistry.baseURL(for: .deepseek, region: descriptor.region) else {
            throw ProviderError.unsupported
        }
        guard
            let slot = descriptor.credentialSlots.first(where: { $0.kind == .apiKey }),
            let key = keychain.key(for: slot.keychainRef)
        else {
            throw ProviderError.invalidKey
        }
        let response = try await http.get(
            base.appendingPathComponent("/user/balance"),
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(BalanceResponse.self, from: response.data)
        var balances: [Money] = []
        for info in body.balanceInfos {
            guard let currency = info.currency else {
                SanitizedLogger.log("deepseek: balance_infos entry without currency skipped")
                continue
            }
            if let amount = info.totalBalance {
                balances.append(Money(role: .available, amount: amount, currency: currency))
            }
            if let amount = info.grantedBalance {
                balances.append(Money(role: .granted, amount: amount, currency: currency))
            }
            if let amount = info.toppedUpBalance {
                balances.append(Money(role: .toppedUp, amount: amount, currency: currency))
            }
        }
        return (balances, body.isAvailable)
    }
}
