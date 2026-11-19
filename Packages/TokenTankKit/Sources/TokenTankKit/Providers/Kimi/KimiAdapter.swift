import Foundation

/// Kimi (Moonshot) adapter. CN and intl are independent platforms with separate keys;
/// the balance comes from `/v1/users/me/balance`. Daily usage and cost come from the
/// Admin API (enterprise Beta) when an `admin` slot is present; admin amounts are in
/// 毫分 and are normalized to `Decimal / 100_000` (1 元 = 100 000 毫分).
/// The Kimi Code subscription limits come from the undocumented coding endpoint
/// `/coding/v1/usages` when a `coding` slot is present (§1): the monthly cap and
/// the 5-hour window, both reported as used ratios.
public struct KimiAdapter: BalanceProvider {
    /// Stable identifier of the Kimi Code 5-hour window quota.
    public static let codingQuotaID = "kimi.coding"
    /// Stable identifier of the Kimi Code monthly quota (combined usage).
    public static let codingMonthQuotaID = "kimi.coding.month"

    public let descriptor: AccountDescriptor
    private let keychain: KeychainClient
    private let http: HTTPClient
    private let tierTable: TierTable?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let bucketFormatter = ISO8601DateFormatter()

    /// - Parameters:
    ///   - descriptor: Account settings.
    ///   - keychain: Source of slot keys.
    ///   - http: HTTP client.
    ///   - tierTable: Tier table for `RateLimits(.tierTable)` (REQ-CFG-7).
    public init(descriptor: AccountDescriptor, keychain: KeychainClient, http: HTTPClient = HTTPClient(), tierTable: TierTable? = nil) {
        self.descriptor = descriptor
        self.keychain = keychain
        self.http = http
        self.tierTable = tierTable
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
                } else if descriptor.credentialSlots.contains(where: { $0.kind == .coding }) {
                    let quotas = try await fetchCodingQuotas(timeout: 3)
                    guard let quota = quotas.first else {
                        throw ProviderError.decoding
                    }
                    result = .success(PrimarySnapshot(scope: .quota(quota.id), fetchedAt: now, balances: nil, quota: quota))
                } else {
                    result = .failure(.unsupported)
                }
            case .quota(let id):
                let quotas = try await fetchCodingQuotas(timeout: 3)
                if let quota = quotas.first(where: { $0.id == id }) {
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
        var balances: [Money]?
        var quotas: [Quota]?
        var usageHistory: [DailyUsage]?

        var limits: RateLimits?
        let apiKeySlot = descriptor.credentialSlots.first(where: { $0.kind == .apiKey })
        if let apiKeySlot {
            do {
                let balance = try await fetchBalance(timeout: 30)
                balances = balance.balances
                limits = balance.headerLimits ?? tierTable?.rateLimits(for: descriptor.tier)
                sections.append(SectionSnapshot(kind: .balance, slotID: apiKeySlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .balance, slotID: apiKeySlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
        } else {
            limits = tierTable?.rateLimits(for: descriptor.tier)
            sections.append(SectionSnapshot(kind: .balance, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        let adminSlot = descriptor.credentialSlots.first(where: { $0.kind == .admin })
        if let adminSlot {
            do {
                guard let key = keychain.key(for: adminSlot.keychainRef) else {
                    throw ProviderError.invalidKey
                }
                usageHistory = try await fetchAdminHistory(key: key, now: now)
                sections.append(SectionSnapshot(kind: .usage, slotID: adminSlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .usage, slotID: adminSlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
        } else {
            sections.append(SectionSnapshot(kind: .usage, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        let codingSlot = descriptor.credentialSlots.first(where: { $0.kind == .coding })
        if let codingSlot {
            do {
                quotas = try await fetchCodingQuotas(timeout: 30)
                sections.append(SectionSnapshot(kind: .quotas, slotID: codingSlot.id, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
            } catch let error as ProviderError {
                sections.append(SectionSnapshot(kind: .quotas, slotID: codingSlot.id, status: .failed(error), lastSuccessAt: nil, lastAttemptAt: now))
            }
        } else {
            sections.append(SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        if limits != nil {
            sections.append(SectionSnapshot(kind: .limits, slotID: nil, status: .ok, lastSuccessAt: now, lastAttemptAt: now))
        } else {
            sections.append(SectionSnapshot(kind: .limits, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil))
        }

        return AccountSnapshot(
            accountID: descriptor.id,
            updatedAt: now,
            isAvailable: nil,
            balances: balances,
            quotas: quotas,
            usageHistory: usageHistory,
            balanceHistory: nil,
            limits: limits,
            modelTopByScope: nil,
            sections: sections
        )
    }

    private func fetchBalance(timeout: TimeInterval) async throws -> (balances: [Money], headerLimits: RateLimits?) {
        struct BalanceResponse: Decodable {
            struct BalanceData: Decodable {
                let availableBalance: Decimal?
                let voucherBalance: Decimal?
                let cashBalance: Decimal?

                enum CodingKeys: String, CodingKey {
                    case availableBalance = "available_balance"
                    case voucherBalance = "voucher_balance"
                    case cashBalance = "cash_balance"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    availableBalance = try container.decodeDecimalIfPresent(forKey: .availableBalance)
                    voucherBalance = try container.decodeDecimalIfPresent(forKey: .voucherBalance)
                    cashBalance = try container.decodeDecimalIfPresent(forKey: .cashBalance)
                }
            }

            let code: Int?
            let data: BalanceData?
        }

        guard
            let region = descriptor.region,
            let base = AdapterRegistry.baseURL(for: .kimi, region: region)
        else {
            throw ProviderError.regionMismatch
        }
        guard
            let slot = descriptor.credentialSlots.first(where: { $0.kind == .apiKey }),
            let key = keychain.key(for: slot.keychainRef)
        else {
            throw ProviderError.invalidKey
        }
        let response = try await http.get(
            base.appendingPathComponent("/v1/users/me/balance"),
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(BalanceResponse.self, from: response.data)
        guard let data = body.data else {
            SanitizedLogger.log("kimi: balance response without data")
            throw ProviderError.decoding
        }
        // The response carries no currency: the registry falls back to the region's
        // platform currency (CN docs: 人民币元, intl docs: unit USD).
        let currency = region == .cn ? "CNY" : "USD"
        var balances: [Money] = []
        if let amount = data.availableBalance {
            balances.append(Money(role: .available, amount: amount, currency: currency))
        }
        if let amount = data.voucherBalance {
            balances.append(Money(role: .voucher, amount: amount, currency: currency))
        }
        if let amount = data.cashBalance {
            balances.append(Money(role: .cash, amount: amount, currency: currency))
        }
        return (balances, RateLimits.fromResponseHeaders(response.headers))
    }

    /// Kimi Code subscription limits from the undocumented coding `usages` endpoint (§1):
    /// the monthly cap (combined usage, with the subscription reset time) and the
    /// 5-hour window. The provider reports only used ratios, so both are percentage
    /// quotas on a 100 % scale.
    private func fetchCodingQuotas(timeout: TimeInterval) async throws -> [Quota] {
        struct CodingUsages: Decodable {
            struct LimitEntry: Decodable {
                struct Window: Decodable {
                    let duration: Int?
                    let timeUnit: String?
                }

                let window: Window?
            }

            struct RatioWindow: Decodable {
                let usedRatio: Decimal?
                let resetTime: String?

                enum CodingKeys: String, CodingKey {
                    case usedRatio = "used_ratio"
                    case resetTime = "reset_time"
                }
            }

            struct Usages: Decodable {
                let limit5h: RatioWindow?
                let limitMonthTotal: RatioWindow?

                enum CodingKeys: String, CodingKey {
                    case limit5h = "limit_5h"
                    case limitMonthTotal = "limit_month_total"
                }
            }

            /// Present in the old response shape only; new plans omit it.
            let limits: [LimitEntry]?
            let usages: Usages?
        }

        guard
            let slot = descriptor.credentialSlots.first(where: { $0.kind == .coding }),
            let key = keychain.key(for: slot.keychainRef)
        else {
            throw ProviderError.invalidKey
        }
        let base = slot.baseURLOverride ?? AdapterRegistry.kimiCodingBaseURL
        let response = try await http.get(
            base.appendingPathComponent("/v1/usages"),
            headers: ["Authorization": "Bearer \(key)"],
            timeout: timeout
        )
        guard (200...299).contains(response.status) else {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
        let body = try decodeProvider(CodingUsages.self, from: response.data)
        var quotas: [Quota] = []
        if let usedRatio = body.usages?.limitMonthTotal?.usedRatio {
            quotas.append(Self.percentQuota(
                id: Self.codingMonthQuotaID,
                usedRatio: usedRatio,
                resetsAt: body.usages?.limitMonthTotal?.resetTime.flatMap { try? Date($0, strategy: .iso8601) },
                period: nil
            ))
        }
        if let usedRatio = body.usages?.limit5h?.usedRatio {
            let reset = body.usages?.limit5h?.resetTime.flatMap { try? Date($0, strategy: .iso8601) }
            let period = reset.map { end -> Period in
                let minutes = body.limits?.first?.window.flatMap { window -> Double? in
                    guard window.timeUnit == "TIME_UNIT_MINUTE", let duration = window.duration else {
                        return nil
                    }
                    return Double(duration)
                } ?? 300
                return Period(start: end.addingTimeInterval(-minutes * 60), end: end)
            }
            quotas.append(Self.percentQuota(id: Self.codingQuotaID, usedRatio: usedRatio, resetsAt: nil, period: period))
        }
        guard quotas.isEmpty == false else {
            SanitizedLogger.log("kimi: coding usages without limits")
            throw ProviderError.decoding
        }
        return quotas
    }

    /// Builds a percentage quota (100 % scale) from a used ratio.
    private static func percentQuota(id: String, usedRatio: Decimal, resetsAt: Date?, period: Period?) -> Quota {
        Quota(
            id: id,
            kind: .subscription,
            unit: .percent,
            total: 100,
            used: usedRatio * 100,
            remaining: (1 - usedRatio) * 100,
            period: period,
            autoRenew: nil,
            resetsAt: resetsAt
        )
    }

    /// Admin usage history for the last 31 days: `usage/completions` (1d) + `billings/daily_bills`.
    private func fetchAdminHistory(key: String, now: Date) async throws -> [DailyUsage] {
        struct DailyBill: Decodable {
            struct ModelDetail: Decodable {
                let modelId: String?
                let tokens: Int64?
                let totalFee: Int64?

                enum CodingKeys: String, CodingKey {
                    case modelId = "model_id"
                    case tokens
                    case totalFee = "total_fee"
                }
            }

            let date: String?
            let totalFee: Int64?
            let modelDetails: [ModelDetail]?

            enum CodingKeys: String, CodingKey {
                case date
                case totalFee = "total_fee"
                case modelDetails = "model_details"
            }
        }

        struct UsageBucket: Decodable {
            let bucketTime: String?
            let modelId: String?
            let promptTokens: Int64?
            let completionTokens: Int64?
            let cachedTokens: Int64?
            let requestCount: Int64?

            enum CodingKeys: String, CodingKey {
                case bucketTime = "bucket_time"
                case modelId = "model_id"
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case cachedTokens = "cached_tokens"
                case requestCount = "request_count"
            }
        }

        let start = Int64(now.addingTimeInterval(-31 * 86_400).timeIntervalSince1970 * 1000)
        let end = Int64(now.timeIntervalSince1970 * 1000)
        let timeQuery = [
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "end", value: String(end)),
        ]
        let bills = try await fetchAllPages(
            DailyBill.self,
            url: AdapterRegistry.kimiAdminBaseURL.appendingPathComponent("/v1/admin/organizations/billings/daily_bills"),
            query: timeQuery + [URLQueryItem(name: "limit", value: "100")],
            key: key
        )
        let buckets = try await fetchAllPages(
            UsageBucket.self,
            url: AdapterRegistry.kimiAdminBaseURL.appendingPathComponent("/v1/admin/organizations/usage/completions"),
            query: timeQuery + [
                URLQueryItem(name: "granularity", value: "1d"),
                URLQueryItem(name: "limit", value: "100"),
            ],
            key: key
        )

        var requestsByDay: [String: Int] = [:]
        var tokensInByDay: [String: Int] = [:]
        var tokensOutByDay: [String: Int] = [:]
        var costByDay: [String: Money] = [:]
        var modelStats: [String: [String: (requests: Int, tokens: Int, fee: Int64)]] = [:]

        for bucket in buckets {
            guard
                let rawTime = bucket.bucketTime,
                let date = Self.bucketFormatter.date(from: rawTime)
            else {
                SanitizedLogger.log("kimi: usage bucket with unparsable time skipped")
                continue
            }
            let day = Self.dayFormatter.string(from: date)
            let prompt = Int(bucket.promptTokens ?? 0)
            let cached = Int(bucket.cachedTokens ?? 0)
            let completion = Int(bucket.completionTokens ?? 0)
            let requests = Int(bucket.requestCount ?? 0)
            requestsByDay[day, default: 0] += requests
            tokensInByDay[day, default: 0] += prompt + cached
            tokensOutByDay[day, default: 0] += completion
            if let model = bucket.modelId {
                var stats = modelStats[day, default: [:]]
                let current = stats[model, default: (0, 0, 0)]
                stats[model] = (current.requests + requests, current.tokens + prompt + cached + completion, current.fee)
                modelStats[day] = stats
            }
        }

        for bill in bills {
            guard let day = bill.date else { continue }
            costByDay[day] = Money(role: .cash, amount: Self.haofen(bill.totalFee ?? 0), currency: "CNY")
            for detail in bill.modelDetails ?? [] {
                guard let model = detail.modelId else { continue }
                var stats = modelStats[day, default: [:]]
                let current = stats[model, default: (0, 0, 0)]
                stats[model] = (current.requests, current.tokens, current.fee + (detail.totalFee ?? 0))
                modelStats[day] = stats
            }
        }

        let days = Set(requestsByDay.keys).union(costByDay.keys).union(modelStats.keys)
        return days.sorted().map { day in
            let models = (modelStats[day] ?? [:]).sorted { $0.key < $1.key }.map { model, stats in
                ModelUsage(
                    model: model,
                    requests: stats.requests == 0 ? nil : stats.requests,
                    tokens: stats.tokens == 0 ? nil : stats.tokens,
                    cost: stats.fee == 0 ? nil : Money(role: .cash, amount: Self.haofen(stats.fee), currency: "CNY")
                )
            }
            return DailyUsage(
                localDay: day,
                timeZoneID: "Asia/Shanghai",
                requests: requestsByDay[day],
                tokensIn: tokensInByDay[day],
                tokensOut: tokensOutByDay[day],
                cost: costByDay[day],
                models: models.isEmpty ? nil : models
            )
        }
    }

    /// Cursor pagination shared by admin endpoints (`has_more` / `next` → `cursor`),
    /// capped at 32 pages.
    private func fetchAllPages<T: Decodable>(_ type: T.Type, url: URL, query: [URLQueryItem], key: String) async throws -> [T] {
        var collected: [T] = []
        var cursor: String?
        var pageCount = 0
        while pageCount < 32 {
            var pageQuery = query
            if let cursor {
                pageQuery.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let response = try await http.get(url, headers: ["Authorization": "Bearer \(key)"], timeout: 30, query: pageQuery)
            guard (200...299).contains(response.status) else {
                throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
            }
            let page = try decodeProvider(AdminPage<T>.self, from: response.data)
            collected.append(contentsOf: page.data)
            pageCount += 1
            guard page.hasMore, let next = page.next else { break }
            cursor = next
        }
        return collected
    }

    /// 毫分 → 元 (1 元 = 100 000 毫分).
    private static func haofen(_ value: Int64) -> Decimal {
        Decimal(value) / 100_000
    }
}

/// Envelope of paginated admin endpoints.
private struct AdminPage<P: Decodable>: Decodable {
    let data: [P]
    let hasMore: Bool
    let next: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case next
    }
}
