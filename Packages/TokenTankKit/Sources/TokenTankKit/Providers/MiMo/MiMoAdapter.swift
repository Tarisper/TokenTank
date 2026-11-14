import Foundation

/// MiMo adapter: Pay-as-you-go (`sk`) and Token Plan (`tp`) slots with independent
/// statuses. Response shapes are documented but not key-verified (probe §9.4),
/// so decoding is fail-closed: an unrecognized form becomes `ProviderError.decoding`
/// and no data is invented.
public struct MiMoAdapter: BalanceProvider {
    /// Stable quota identifier of the Token Plan.
    public static let quotaID = "mimo.tokenplan"

    public let descriptor: AccountDescriptor
    private let keychain: KeychainClient
    private let http: HTTPClient

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `period.start_at`/`end_at` are UTC strings `YYYY-MM-DD HH:mm:ss`
    /// (documented in credits-get / token_plan; probe confirms on a live key).
    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// - Parameters:
    ///   - descriptor: Account settings.
    ///   - keychain: Source of slot keys.
    ///   - http: HTTP client.
    public init(descriptor: AccountDescriptor, keychain: KeychainClient, http: HTTPClient = HTTPClient()) {
        self.descriptor = descriptor
        self.keychain = keychain
        self.http = http
    }

    public func fetchPrimary(scope: Scope) async -> Result<PrimarySnapshot, ProviderError> {
        let now = Date()
        let result: Result<PrimarySnapshot, ProviderError>
        do {
            switch scope {
            case .account:
                if descriptor.credentialSlots.contains(where: { $0.kind == .apiKey }) {
                    let balance = try await fetchBalance(timeout: 3)
                    result = .success(PrimarySnapshot(scope: scope, fetchedAt: now, balances: balance.balances, quota: nil))
                } else if descriptor.credentialSlots.contains(where: { $0.kind == .tokenPlan }) {
                    let quota = try await fetchTokenPlan(timeout: 3)
                    result = .success(PrimarySnapshot(scope: .quota(quota.id), fetchedAt: now, balances: nil, quota: quota))
                } else {
                    result = .failure(.unsupported)
                }
            case .quota(let id):
                if id == Self.quotaID {
                    let quota = try await fetchTokenPlan(timeout: 3)
                    result = .success(PrimarySnapshot(scope: scope, fetchedAt: now, balances: nil, quota: quota))
                } else {
                    result = .failure(.unsupported)
                }
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
        var sections: [SectionSnapshot] = []
        var isAvailable: Bool?
        var balances: [Money]?
        var quotas: [Quota]?
        var usageHistory: [DailyUsage]?

        let tpSlot = descriptor.credentialSlots.first(where: { $0.kind == .tokenPlan })
        if let tpSlot {
            do {
                let quota = try await fetchTokenPlan(timeout: 10)
                quotas = [quota]
                sections.append(SectionSnapshot(kind: .quotas, slotID: tpSlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .quotas, slotID: tpSlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
        } else {
            sections.append(SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        let skSlot = descriptor.credentialSlots.first(where: { $0.kind == .apiKey })
        if let skSlot {
            do {
                let balance = try await fetchBalance(timeout: 10)
                balances = balance.balances
                isAvailable = balance.isAvailable
                sections.append(SectionSnapshot(kind: .balance, slotID: skSlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .balance, slotID: skSlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
            // Usage follows the retention window (§3.5), not the tp quota
            // period: quota periods feed `.quota` aggregations only (M6).
            let usagePeriod = Period(
                start: now.addingTimeInterval(-TimeInterval(UsageHistory.baseRetentionDays) * 86_400),
                end: now
            )
            do {
                usageHistory = try await fetchUsageHistory(period: usagePeriod, timeout: 10)
                sections.append(SectionSnapshot(kind: .usage, slotID: skSlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .usage, slotID: skSlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
        } else {
            sections.append(SectionSnapshot(kind: .balance, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
            sections.append(SectionSnapshot(kind: .usage, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        sections.append(SectionSnapshot(kind: .limits, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))

        return AccountSnapshot(
            accountID: descriptor.id,
            updatedAt: now,
            isAvailable: isAvailable,
            balances: balances,
            quotas: quotas,
            usageHistory: usageHistory,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: sections
        )
    }

    private func fetchBalance(timeout: TimeInterval) async throws -> (balances: [Money], isAvailable: Bool?) {
        struct BalanceResponse: Decodable {
            struct BalanceInfo: Decodable {
                let currency: String?
                let cashBalance: Decimal?
                let giftBalance: Decimal?
                let frozenBalance: Decimal?
                let creditLimit: Decimal?
                let creditAvailable: Decimal?
                let totalAvailable: Decimal?

                enum CodingKeys: String, CodingKey {
                    case currency
                    case cashBalance = "cash_balance"
                    case giftBalance = "gift_balance"
                    case frozenBalance = "frozen_balance"
                    case creditLimit = "credit_limit"
                    case creditAvailable = "credit_available"
                    case totalAvailable = "total_available"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    currency = try container.decodeIfPresent(String.self, forKey: .currency)
                    cashBalance = try container.decodeDecimalIfPresent(forKey: .cashBalance)
                    giftBalance = try container.decodeDecimalIfPresent(forKey: .giftBalance)
                    frozenBalance = try container.decodeDecimalIfPresent(forKey: .frozenBalance)
                    creditLimit = try container.decodeDecimalIfPresent(forKey: .creditLimit)
                    creditAvailable = try container.decodeDecimalIfPresent(forKey: .creditAvailable)
                    totalAvailable = try container.decodeDecimalIfPresent(forKey: .totalAvailable)
                }
            }

            let object: String?
            let isAvailable: Bool?
            let balanceInfos: [BalanceInfo]

            enum CodingKeys: String, CodingKey {
                case object
                case isAvailable = "is_available"
                case balanceInfos = "balance_infos"
            }
        }

        let key = try slotKey(.apiKey)
        let url = try skBaseURL().appendingPathComponent("/v1/platform/balance")
        let response = try await http.get(url, headers: ["Authorization": "Bearer \(key)"], timeout: timeout)
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(BalanceResponse.self, from: response.data)
        guard body.object == "balance" else {
            SanitizedLogger.log("mimo: unexpected balance form \(body.object ?? "nil")")
            throw ProviderError.decoding
        }
        var balances: [Money] = []
        for info in body.balanceInfos {
            guard let currency = info.currency else {
                SanitizedLogger.log("mimo: balance_infos entry without currency skipped")
                continue
            }
            if let amount = info.totalAvailable {
                balances.append(Money(role: .available, amount: amount, currency: currency))
            }
            if let amount = info.cashBalance {
                balances.append(Money(role: .cash, amount: amount, currency: currency))
            }
            if let amount = info.giftBalance {
                balances.append(Money(role: .gift, amount: amount, currency: currency))
            }
            if let amount = info.frozenBalance {
                balances.append(Money(role: .frozen, amount: amount, currency: currency))
            }
            if let amount = info.creditLimit {
                balances.append(Money(role: .creditLimit, amount: amount, currency: currency))
            }
            if let amount = info.creditAvailable {
                balances.append(Money(role: .creditAvailable, amount: amount, currency: currency))
            }
        }
        return (balances, body.isAvailable)
    }

    private func fetchTokenPlan(timeout: TimeInterval) async throws -> Quota {
        struct TokenPlanResponse: Decodable {
            struct QuotaData: Decodable {
                let totalCredits: Decimal?
                let usedCredits: Decimal?
                let remainingCredits: Decimal?

                enum CodingKeys: String, CodingKey {
                    case totalCredits = "total_credits"
                    case usedCredits = "used_credits"
                    case remainingCredits = "remaining_credits"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    totalCredits = try container.decodeDecimalIfPresent(forKey: .totalCredits)
                    usedCredits = try container.decodeDecimalIfPresent(forKey: .usedCredits)
                    remainingCredits = try container.decodeDecimalIfPresent(forKey: .remainingCredits)
                }
            }

            struct PeriodData: Decodable {
                let startAt: String?
                let endAt: String?

                enum CodingKeys: String, CodingKey {
                    case startAt = "start_at"
                    case endAt = "end_at"
                }
            }

            let quota: QuotaData?
            let period: PeriodData?
            let autoRenew: Bool?

            enum CodingKeys: String, CodingKey {
                case quota
                case period
                case autoRenew = "auto_renew"
            }
        }

        let key = try slotKey(.tokenPlan)
        let slot = descriptor.credentialSlots.first(where: { $0.kind == .tokenPlan })
        let base = slot?.baseURLOverride ?? AdapterRegistry.mimoTokenPlanDefaultBaseURL
        let response = try await http.get(
            base.appendingPathComponent("/v1/platform/token_plan"),
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(TokenPlanResponse.self, from: response.data)
        guard let quotaData = body.quota else {
            SanitizedLogger.log("mimo: token_plan response without quota")
            throw ProviderError.decoding
        }
        let period: Period?
        if
            let startRaw = body.period?.startAt,
            let endRaw = body.period?.endAt,
            let startAt = Self.periodFormatter.date(from: startRaw),
            let endAt = Self.periodFormatter.date(from: endRaw)
        {
            period = Period(start: startAt, end: endAt)
        } else {
            period = nil
        }
        return Quota(
            id: Self.quotaID,
            kind: .tokenPlan,
            unit: .credits,
            total: quotaData.totalCredits,
            used: quotaData.usedCredits,
            remaining: quotaData.remainingCredits,
            period: period,
            autoRenew: body.autoRenew
        )
    }

    private func fetchUsageHistory(period: Period, timeout: TimeInterval) async throws -> [DailyUsage] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var usageChunks: [[DailyUsage]] = []
        var paidByDay: [String: Money] = [:]
        for window in UsageChunking.windows(in: period, calendar: calendar) {
            usageChunks.append(try await fetchDailyUsage(window: window, timeout: timeout))
            for (day, money) in try await fetchDailyBilling(window: window, timeout: timeout) {
                paidByDay[day] = money
            }
        }
        let merged = UsageChunking.merge(usageChunks)
        var result = merged.map { usage in
            DailyUsage(
                localDay: usage.localDay,
                timeZoneID: usage.timeZoneID,
                requests: usage.requests,
                tokensIn: usage.tokensIn,
                tokensOut: usage.tokensOut,
                cost: paidByDay[usage.localDay] ?? usage.cost,
                models: usage.models
            )
        }
        for (day, money) in paidByDay where merged.contains(where: { $0.localDay == day }) == false {
            result.append(DailyUsage(localDay: day, timeZoneID: "UTC", requests: nil, tokensIn: nil, tokensOut: nil, cost: money, models: nil))
        }
        return result.sorted { $0.localDay < $1.localDay }
    }

    private func fetchDailyUsage(window: Period, timeout: TimeInterval) async throws -> [DailyUsage] {
        struct UsageList: Decodable {
            struct UsageRecord: Decodable {
                let date: String?
                let resourceType: String?
                let name: String?
                let currency: String?
                let consumedAmount: Decimal?
                let totalTokens: Int?
                let inputCacheHitTokens: Int?
                let inputCacheMissTokens: Int?
                let outputTokens: Int?
                let requestCount: Int?

                enum CodingKeys: String, CodingKey {
                    case date
                    case resourceType = "resource_type"
                    case name
                    case currency
                    case consumedAmount = "consumed_amount"
                    case totalTokens = "total_tokens"
                    case inputCacheHitTokens = "input_cache_hit_tokens"
                    case inputCacheMissTokens = "input_cache_miss_tokens"
                    case outputTokens = "output_tokens"
                    case requestCount = "request_count"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    date = try container.decodeIfPresent(String.self, forKey: .date)
                    resourceType = try container.decodeIfPresent(String.self, forKey: .resourceType)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    currency = try container.decodeIfPresent(String.self, forKey: .currency)
                    consumedAmount = try container.decodeDecimalIfPresent(forKey: .consumedAmount)
                    totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
                    inputCacheHitTokens = try container.decodeIfPresent(Int.self, forKey: .inputCacheHitTokens)
                    inputCacheMissTokens = try container.decodeIfPresent(Int.self, forKey: .inputCacheMissTokens)
                    outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
                    requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount)
                }
            }

            let object: String?
            let data: [UsageRecord]
        }

        let key = try slotKey(.apiKey)
        let url = try skBaseURL().appendingPathComponent("/v1/platform/usage/daily")
        let response = try await http.get(
            url,
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout,
            query: dayQuery(window)
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(UsageList.self, from: response.data)
        guard body.object == "list" else {
            SanitizedLogger.log("mimo: unexpected usage form \(body.object ?? "nil")")
            throw ProviderError.decoding
        }

        var recordsByDay: [String: [UsageList.UsageRecord]] = [:]
        for record in body.data {
            guard let day = record.date else { continue }
            recordsByDay[day, default: []].append(record)
        }
        return recordsByDay.sorted { $0.key < $1.key }.map { day, records in
            let models = records.compactMap { record -> ModelUsage? in
                guard record.resourceType == "model", let name = record.name else { return nil }
                var cost: Money?
                if let amount = record.consumedAmount, let currency = record.currency {
                    cost = Money(role: .cash, amount: amount, currency: currency)
                }
                return ModelUsage(model: name, requests: record.requestCount, tokens: record.totalTokens, cost: cost)
            }
            let tokensIn = records.reduce(0) { $0 + ($1.inputCacheHitTokens ?? 0) + ($1.inputCacheMissTokens ?? 0) }
            let tokensOut = records.reduce(0) { $0 + ($1.outputTokens ?? 0) }
            let requests = records.reduce(0) { $0 + ($1.requestCount ?? 0) }
            return DailyUsage(
                localDay: day,
                timeZoneID: "UTC",
                requests: requests,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                cost: nil,
                models: models.isEmpty ? nil : models
            )
        }
    }

    private func fetchDailyBilling(window: Period, timeout: TimeInterval) async throws -> [String: Money] {
        struct BillingList: Decodable {
            struct BillingRecord: Decodable {
                let date: String?
                let currency: String?
                let finalPaidAmount: Decimal?

                enum CodingKeys: String, CodingKey {
                    case date
                    case currency
                    case finalPaidAmount = "final_paid_amount"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    date = try container.decodeIfPresent(String.self, forKey: .date)
                    currency = try container.decodeIfPresent(String.self, forKey: .currency)
                    finalPaidAmount = try container.decodeDecimalIfPresent(forKey: .finalPaidAmount)
                }
            }

            let object: String?
            let data: [BillingRecord]
        }

        let key = try slotKey(.apiKey)
        let url = try skBaseURL().appendingPathComponent("/v1/platform/billing/daily")
        let response = try await http.get(
            url,
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout,
            query: dayQuery(window)
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(BillingList.self, from: response.data)
        guard body.object == "list" else {
            SanitizedLogger.log("mimo: unexpected billing form \(body.object ?? "nil")")
            throw ProviderError.decoding
        }
        var paidByDay: [String: Money] = [:]
        for record in body.data {
            guard let day = record.date, let amount = record.finalPaidAmount, let currency = record.currency else { continue }
            paidByDay[day] = Money(role: .cash, amount: amount, currency: currency)
        }
        return paidByDay
    }

    private func dayQuery(_ window: Period) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start_date", value: Self.dayFormatter.string(from: window.start)),
            URLQueryItem(name: "end_date", value: Self.dayFormatter.string(from: window.end)),
        ]
    }

    private func skBaseURL() throws -> URL {
        guard let base = AdapterRegistry.baseURL(for: .mimo, region: descriptor.region) else {
            throw ProviderError.unsupported
        }
        return base
    }

    private func slotKey(_ kind: KeyKind) throws -> String {
        guard
            let slot = descriptor.credentialSlots.first(where: { $0.kind == kind }),
            let key = keychain.key(for: slot.keychainRef)
        else {
            throw ProviderError.invalidKey
        }
        return key
    }

}
