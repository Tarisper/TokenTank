import Foundation
import TokenTankKit

/// Resolved widget parameters: the only layer that reads snapshots (§4).
public struct WidgetViewState {
    /// What the small widget shows next to the balance.
    public enum Display {
        /// Gauge with preformatted center and caption texts.
        case ring(fraction: Double?, centerText: String, captionText: String)
        /// «Not enough data» (no forecast, no quota).
        case noData(text: String)
    }

    /// Parameters of one progress bar.
    public struct BarParams {
        public let kind: BarKind
        public let valueText: String
        public let fraction: Double
        /// Per-limit caption overriding the generic bar kind label.
        public let caption: String?
        /// Preformatted reset hint (e.g. «until 01:59»).
        public let resetText: String?
    }

    /// Small widget layout.
    public struct Small {
        public let status: StatusKind
        public let statusText: String?
        public let label: String
        public let balanceText: String?
        public let display: Display
        /// Quota bars for the `bars` small layout.
        public let bars: [BarParams]
        /// Absolute update time («updated at 12:34»).
        public let updatedAtText: String?
    }

    /// Top-models layout (REQ-TOP).
    public struct TopModels {
        public struct Row {
            public let name: String
            /// Preformatted spend/limit (or share) with its unit.
            public let valueText: String
            /// Bar fraction of the scope total; `nil` renders without a bar.
            public let fraction: Double?
        }

        public let status: StatusKind
        public let statusText: String?
        public let titleText: String
        public let rows: [Row]
        public let emptyText: String?
    }

    /// One row of the medium widget.
    public struct Row {
        public let label: String
        public let balanceText: String
        public let detailText: String?
        public let status: StatusKind
        public let statusText: String?
    }

    /// Medium widget layout: a focused account (quota bars) or the account list.
    public struct Medium {
        /// Detail of the account selected in the widget configuration.
        public struct Focus {
            public let label: String
            public let status: StatusKind
            public let statusText: String?
            public let bars: [BarParams]
        }

        public let focus: Focus?
        public let rows: [Row]
        public let emptyText: String?
        /// Localized update time of the focused account; `nil` for the account list.
        public let updatedAtText: String?
    }
}

/// Maps `AccountSnapshot` + settings to widget view parameters: priority matrix
/// `error` > `stale`(+`low`) > `low` > `ok`, display currency resolution and
/// system formatting. The menu bar and the widgets share these results.
public enum ViewStateBuilder {
    /// Data is stale after two default polling intervals without success (§2).
    public static let staleness: TimeInterval = 30 * 60
    /// Forecast ring scale (§3.5): up to 90 days is a full ring.
    public static let forecastScaleDays = 90.0

    /// Resolves the display currency: explicit setting or the first `.available`
    /// currency of the last response (§3.1).
    /// - Parameters:
    ///   - account: Account settings.
    ///   - snapshot: Last snapshot, if any.
    /// - Returns: ISO 4217 code, or `nil` when nothing is known yet.
    public static func displayCurrency(of account: AccountDescriptor, snapshot: AccountSnapshot?) -> String? {
        if let currency = account.displayCurrency {
            return currency
        }
        return snapshot?.balances?.first(where: { $0.role == .available })?.currency
    }

    /// Preformatted balance of the account: one amount per `.available` currency,
    /// the display currency first (no conversion between currencies).
    /// - Parameters:
    ///   - account: Account settings.
    ///   - snapshot: Last snapshot, if any.
    ///   - locale: Formatting locale.
    /// - Returns: `"$0.17 · ¥15.48"`, or `nil` when no balance is known.
    public static func balanceText(of account: AccountDescriptor, snapshot: AccountSnapshot?, locale: Locale = .current) -> String? {
        formattedBalance(
            balances: snapshot?.balances,
            currency: displayCurrency(of: account, snapshot: snapshot),
            locale: locale
        )
    }

    /// Formats one amount per `.available` currency (first entry per currency wins)
    /// and moves `currency` to the front.
    private static func formattedBalance(balances: [Money]?, currency: String?, locale: Locale) -> String? {
        var ordered: [Money] = []
        for money in balances ?? [] where money.role == .available {
            guard ordered.contains(where: { $0.currency == money.currency }) == false else { continue }
            ordered.append(money)
        }
        if let currency, let index = ordered.firstIndex(where: { $0.currency == currency }), index > 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        guard ordered.isEmpty == false else {
            return nil
        }
        return ordered
            .map { $0.amount.formatted(.currency(code: $0.currency).locale(locale)) }
            .joined(separator: " · ")
    }

    /// Builds the small widget layout.
    /// - Parameters:
    ///   - account: Account settings.
    ///   - snapshot: Last snapshot, if any.
    ///   - now: Current time (staleness check).
    /// - Returns: Layout parameters.
    public static func small(account: AccountDescriptor, snapshot: AccountSnapshot?, now: Date = Date(), locale: Locale = .current) -> WidgetViewState.Small {
        let (status, statusText) = resolveStatus(account: account, snapshot: snapshot, now: now, locale: locale)
        let currency = displayCurrency(of: account, snapshot: snapshot)
        return WidgetViewState.Small(
            status: status,
            statusText: statusText,
            label: account.label,
            balanceText: balanceText(of: account, snapshot: snapshot, locale: locale),
            display: resolveDisplay(
                quotas: snapshot?.quotas,
                history: snapshot?.balanceHistory,
                currency: currency ?? snapshot?.balanceHistory?.first?.currency ?? "",
                locale: locale
            ),
            bars: quotaBars(quotas: snapshot?.quotas, locale: locale),
            updatedAtText: snapshot.map { updatedAtText(for: $0.updatedAt, locale: locale) }
        )
    }

    private static func updatedAtText(for date: Date, locale: Locale) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        return String(localized: "widget.updatedAt \(time)", bundle: .module, locale: locale)
    }

    /// Builds the small layout from a lightweight primary snapshot (active mode).
    /// - Parameters:
    ///   - account: Account settings.
    ///   - primary: `fetchPrimary` result (display-only).
    ///   - locale: Formatting locale.
    /// - Returns: Layout parameters with `.ok` status (data is fresh).
    public static func small(account: AccountDescriptor, primary: PrimarySnapshot, locale: Locale = .current) -> WidgetViewState.Small {
        let currency = account.displayCurrency
            ?? primary.balances?.first(where: { $0.role == .available })?.currency
        return WidgetViewState.Small(
            status: .ok,
            statusText: nil,
            label: account.label,
            balanceText: formattedBalance(balances: primary.balances, currency: currency, locale: locale),
            display: resolveDisplay(
                quotas: primary.quota.map { [$0] },
                history: nil,
                currency: currency ?? "",
                locale: locale
            ),
            bars: quotaBars(quotas: primary.quota.map { [$0] }, locale: locale),
            updatedAtText: updatedAtText(for: primary.fetchedAt, locale: locale)
        )
    }

    /// Builds the medium widget layout.
    /// - Parameters:
    ///   - accounts: Accounts in display order.
    ///   - snapshots: Snapshots by account id.
    ///   - focusAccountID: Account selected in the widget configuration; when it has
    ///     quota bars, the layout shows them instead of the account list.
    ///   - now: Current time (staleness check).
    ///   - locale: Formatting locale.
    /// - Returns: Layout parameters.
    public static func medium(
        accounts: [AccountDescriptor],
        snapshots: [UUID: AccountSnapshot],
        focusAccountID: UUID? = nil,
        now: Date = Date(),
        locale: Locale = .current
    ) -> WidgetViewState.Medium {
        if let focusAccountID, let account = accounts.first(where: { $0.id == focusAccountID }) {
            let snapshot = snapshots[account.id]
            let bars = quotaBars(quotas: snapshot?.quotas, locale: locale, showsReset: true)
            if bars.isEmpty == false {
                let (status, statusText) = resolveStatus(account: account, snapshot: snapshot, now: now, locale: locale)
                return WidgetViewState.Medium(
                    focus: WidgetViewState.Medium.Focus(
                        label: account.label,
                        status: status,
                        statusText: statusText,
                        bars: bars
                    ),
                    rows: [],
                    emptyText: nil,
                    updatedAtText: snapshot.map { updatedAtText(for: $0.updatedAt, locale: locale) }
                )
            }
        }
        let rows = accounts.map { account -> WidgetViewState.Row in
            let snapshot = snapshots[account.id]
            let (status, statusText) = resolveStatus(account: account, snapshot: snapshot, now: now, locale: locale)
            let balance = balanceText(of: account, snapshot: snapshot, locale: locale)
            let limits = limitsText(of: account, snapshot: snapshot, locale: locale)
            let value = [balance, limits].compactMap { $0 }.joined(separator: " · ")
            return WidgetViewState.Row(
                label: account.label,
                balanceText: value.isEmpty ? "—" : value,
                detailText: forecastPhrase(account: account, snapshot: snapshot, locale: locale),
                status: status,
                statusText: statusText
            )
        }
        return WidgetViewState.Medium(
            focus: nil,
            rows: rows,
            emptyText: rows.isEmpty ? String(localized: "widget.addAccount", bundle: .module, locale: locale) : nil,
            updatedAtText: nil
        )
    }

    /// Builds the small layout from the active-mode fetch result (M3 review):
    /// credential failures (`invalidKey`/`regionMismatch`) render as `.error`,
    /// transient ones fall back to the passive snapshot plus the failed flag.
    /// - Parameters:
    ///   - account: Account settings.
    ///   - primaryResult: Result of the active-mode `fetchPrimary`.
    ///   - snapshot: Last snapshot (fallback data).
    ///   - now: Current time (staleness check).
    ///   - locale: Formatting locale.
    /// - Returns: Layout parameters and the «could not update» flag.
    public static func small(
        account: AccountDescriptor,
        primaryResult: Result<PrimarySnapshot, ProviderError>,
        snapshot: AccountSnapshot?,
        now: Date = Date(),
        locale: Locale = .current
    ) -> (state: WidgetViewState.Small, activeFailed: Bool) {
        switch primaryResult {
        case .success(let primary):
            return (small(account: account, primary: primary, locale: locale), false)
        case .failure(let error) where error.isCredentialFailure:
            let passive = small(account: account, snapshot: snapshot, now: now, locale: locale)
            let state = WidgetViewState.Small(
                status: .error,
                statusText: String(localized: "widget.status.error \(ProviderErrorText.text(for: error, locale: locale))", bundle: .module, locale: locale),
                label: passive.label,
                balanceText: passive.balanceText,
                display: passive.display,
                bars: passive.bars,
                updatedAtText: passive.updatedAtText
            )
            return (state, false)
        case .failure:
            return (small(account: account, snapshot: snapshot, now: now, locale: locale), true)
        }
    }

    /// Builds the top-models layout from `modelTopByScope` (§3.2, REQ-TOP).
    ///
    /// States: `error` (fetch failed) > `stale` > `zeroSpend` (records exist but
    /// no spend) / `noData` (no records) / `unsupported` (provider has no model
    /// usage API) / `ok`. `noData` and `zeroSpend` are different states.
    /// Bars use one denominator — the scope total (REQ-TOP-1): the account
    /// budget for `.account`, quota total for `.quota`; without a budget the
    /// rows show shares without bars. `.quota` rows are bar-less — final for
    /// v1.0: the probe (13.11.2026) confirmed no per-model credits in the
    /// responses («tokens × price» is forbidden, REQ-TOP-2).
    /// - Parameters:
    ///   - account: Account settings (budgets).
    ///   - snapshot: Last snapshot, if any.
    ///   - scope: Aggregation scope.
    ///   - now: Current time (staleness check).
    ///   - locale: Formatting locale.
    /// - Returns: Layout parameters.
    public static func topModels(
        account: AccountDescriptor,
        snapshot: AccountSnapshot?,
        scope: Scope,
        now: Date = Date(),
        locale: Locale = .current
    ) -> WidgetViewState.TopModels {
        let titleText = String(localized: "widget.topModels", bundle: .module, locale: locale)
        let emptyText = String(localized: "widget.empty", bundle: .module, locale: locale)
        guard let snapshot else {
            return WidgetViewState.TopModels(status: .empty, statusText: emptyText, titleText: titleText, rows: [], emptyText: emptyText)
        }
        let stale = now.timeIntervalSince(snapshot.updatedAt) > staleness
        let age = relativeFormatterText(from: snapshot.updatedAt, to: now, locale: locale)
        let staleText = String(localized: "widget.status.stale \(age)", bundle: .module, locale: locale)

        let status: StatusKind
        var statusText: String?
        var rows: [WidgetViewState.TopModels.Row] = []
        var rowsEmptyText: String?

        let usageStatus = snapshot.sections.first(where: { $0.kind == .usage })?.status
        switch usageStatus {
        case .failed(let error):
            status = .error
            statusText = String(localized: "widget.status.error \(ProviderErrorText.text(for: error, locale: locale))", bundle: .module, locale: locale)
        case .unsupported:
            status = .unsupported
            rowsEmptyText = String(localized: "widget.unsupported", bundle: .module, locale: locale)
        case .none:
            status = .noData
            rowsEmptyText = String(localized: "widget.noData", bundle: .module, locale: locale)
        case .ok:
            let usages = snapshot.modelTopByScope?[scope.rawValue] ?? []
            if usages.isEmpty {
                status = stale ? .stale : .noData
                statusText = stale ? staleText : nil
                rowsEmptyText = String(localized: "widget.noData", bundle: .module, locale: locale)
            } else if usages.allSatisfy({ ($0.cost?.amount ?? 0) == 0 && ($0.tokens ?? 0) == 0 }) {
                status = stale ? .stale : .zeroSpend
                statusText = stale ? staleText : nil
                rowsEmptyText = String(localized: "widget.zeroSpend", bundle: .module, locale: locale)
            } else {
                status = stale ? .stale : .ok
                statusText = stale ? staleText : nil
                rows = topRows(usages: usages, account: account, snapshot: snapshot, scope: scope, locale: locale)
            }
        }
        return WidgetViewState.TopModels(
            status: status,
            statusText: statusText,
            titleText: titleText,
            rows: rows,
            emptyText: rowsEmptyText
        )
    }

    private static func topRows(
        usages: [ModelUsage],
        account: AccountDescriptor,
        snapshot: AccountSnapshot?,
        scope: Scope,
        locale: Locale
    ) -> [WidgetViewState.TopModels.Row] {
        if case .quota = scope {
            // Bar-less is final for v1.0 (probe 13.11.2026: no per-model credits).
            return usages.map {
                WidgetViewState.TopModels.Row(name: $0.model, valueText: tokenText($0, locale: locale), fraction: nil)
            }
        }
        let currency = displayCurrency(of: account, snapshot: snapshot)
        let budget = account.budgets.first { $0.currency == currency } ?? account.budgets.first
        if let budget, budget.amount > 0 {
            return usages.map { usage in
                if let cost = usage.cost, cost.currency == budget.currency {
                    let spentText = cost.amount.formatted(.number.locale(locale))
                    let budgetText = budget.amount.formatted(.number.locale(locale))
                    return WidgetViewState.TopModels.Row(
                        name: usage.model,
                        valueText: "\(spentText) / \(budgetText) \(budget.currency)",
                        fraction: Double(truncating: (cost.amount / budget.amount) as NSDecimalNumber)
                    )
                }
                return WidgetViewState.TopModels.Row(name: usage.model, valueText: tokenText(usage, locale: locale), fraction: nil)
            }
        }
        // Shares without bars (REQ-TOP-4): money share when costs are uniform,
        // token share otherwise (no currency conversion).
        let currencies = Set(usages.compactMap { $0.cost?.currency })
        let moneyShare = currencies.count == 1
        let total = moneyShare
            ? usages.compactMap { $0.cost?.amount }.reduce(Decimal(0), +)
            : Decimal(usages.reduce(0) { $0 + ($1.tokens ?? 0) })
        return usages.map { usage in
            let value = moneyShare ? (usage.cost?.amount ?? 0) : Decimal(usage.tokens ?? 0)
            let share = total > 0 ? Double(truncating: (value / total) as NSDecimalNumber) : 0
            return WidgetViewState.TopModels.Row(
                name: usage.model,
                valueText: share.formatted(.percent.precision(.fractionLength(0)).locale(locale)),
                fraction: nil
            )
        }
    }

    private static func tokenText(_ usage: ModelUsage, locale: Locale) -> String {
        (usage.tokens ?? 0).formatted(.number.locale(locale))
    }

    private static func relativeFormatterText(from: Date, to: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return formatter.localizedString(for: from, relativeTo: to)
    }

    private static func resolveStatus(account: AccountDescriptor, snapshot: AccountSnapshot?, now: Date, locale: Locale) -> (StatusKind, String?) {
        guard let snapshot else {
            return (.empty, String(localized: "widget.empty", bundle: .module, locale: locale))
        }
        let failures = snapshot.sections.compactMap { section -> ProviderError? in
            if case .failed(let error) = section.status {
                return error
            }
            return nil
        }
        if failures.isEmpty == false, failures.count == snapshot.sections.count {
            return (.error, String(localized: "widget.status.error \(ProviderErrorText.text(for: failures[0], locale: locale))", bundle: .module, locale: locale))
        }
        let stale = now.timeIntervalSince(snapshot.updatedAt) > staleness
        let low = isLow(account: account, snapshot: snapshot)
        let age = relativeFormatterText(from: snapshot.updatedAt, to: now, locale: locale)
        if stale, low {
            let staleText = String(localized: "widget.status.stale \(age)", bundle: .module, locale: locale)
            let lowText = String(localized: "widget.status.low", bundle: .module, locale: locale)
            return (.stale, String(localized: "widget.status.staleLow \(staleText) \(lowText)", bundle: .module, locale: locale))
        }
        if stale {
            return (.stale, String(localized: "widget.status.stale \(age)", bundle: .module, locale: locale))
        }
        if low {
            return (.low, String(localized: "widget.status.low", bundle: .module, locale: locale))
        }
        return (.ok, nil)
    }

    private static func isLow(account: AccountDescriptor, snapshot: AccountSnapshot) -> Bool {
        for threshold in account.thresholds {
            if let currency = threshold.currency {
                let available = snapshot.balances?
                    .first(where: { $0.role == .available && $0.currency == currency })?.amount
                if let available, available <= threshold.value {
                    return true
                }
            } else if threshold.unit != nil, let quotaID = threshold.quotaID {
                let quota = snapshot.quotas?.first(where: { $0.id == quotaID })
                if let remaining = quota?.remaining, remaining <= threshold.value {
                    return true
                }
            }
        }
        return false
    }

    private static func daysLeft(history: [BalancePoint]?, currency: String) -> Int? {
        if case .days(let count) = Forecast.daysLeft(history: history ?? [], currency: currency) {
            return count
        }
        return nil
    }

    private static func forecastPhrase(account: AccountDescriptor, snapshot: AccountSnapshot?, locale: Locale) -> String? {
        let currency = displayCurrency(of: account, snapshot: snapshot)
            ?? snapshot?.balanceHistory?.first?.currency
            ?? ""
        guard let count = daysLeft(history: snapshot?.balanceHistory, currency: currency) else { return nil }
        return String(localized: "widget.daysRemaining \(count)", bundle: .module, locale: locale)
    }

    private static func resolveDisplay(quotas: [Quota]?, history: [BalancePoint]?, currency: String, locale: Locale) -> WidgetViewState.Display {
        if
            let quota = quotas?.first(where: { $0.total != nil }),
            let total = quota.total,
            total > 0,
            let used = quota.used
        {
            let fraction = Double(truncating: (used / total) as NSDecimalNumber)
            let percentText = fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
            return .ring(
                fraction: fraction,
                centerText: percentText,
                captionText: String(localized: "widget.quotaCaption", bundle: .module, locale: locale)
            )
        }
        if let count = daysLeft(history: history, currency: currency) {
            return .ring(
                fraction: min(Double(count) / forecastScaleDays, 1),
                centerText: count.formatted(.number.locale(locale)),
                captionText: String(localized: "widget.daysCaption", bundle: .module, locale: locale)
            )
        }
        return .noData(text: String(localized: "widget.noData", bundle: .module, locale: locale))
    }

    /// Short limits line: Kimi Code monthly/5-hour used shares and the 5-hour
    /// reset time (`78,7 %/13 % 01:59`), or the used share of the first quota
    /// (MiMo Token Plan: `18,7 %`).
    /// - Parameters:
    ///   - account: Account settings.
    ///   - snapshot: Last snapshot, if any.
    ///   - locale: Formatting locale.
    /// - Returns: Preformatted line, or `nil` when the account has no quotas.
    public static func limitsText(of account: AccountDescriptor, snapshot: AccountSnapshot?, locale: Locale = .current) -> String? {
        let quotas = snapshot?.quotas ?? []
        let monthly = quotas.first { $0.id == KimiAdapter.codingMonthQuotaID }
        let fiveHour = quotas.first { $0.id == KimiAdapter.codingQuotaID }
        if
            let monthly,
            let fiveHour,
            let monthlyText = quotaPercentText(monthly, fractionDigits: 1, locale: locale),
            let fiveHourText = quotaPercentText(fiveHour, fractionDigits: 0, locale: locale)
        {
            let reset = fiveHour.period?.end.formatted(.dateTime.hour().minute().locale(locale))
            return [monthlyText, fiveHourText].joined(separator: "/") + (reset.map { " \($0)" } ?? "")
        }
        if let quota = quotas.first(where: { $0.total != nil && $0.used != nil }) {
            return quotaPercentText(quota, fractionDigits: 1, locale: locale)
        }
        return nil
    }

    /// Used share of a quota as a percentage string.
    private static func quotaPercentText(_ quota: Quota, fractionDigits: Int, locale: Locale) -> String? {
        guard let total = quota.total, total > 0, let used = quota.used else { return nil }
        let fraction = Double(truncating: (used / total) as NSDecimalNumber)
        return fraction.formatted(.percent.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    private static func quotaBars(quotas: [Quota]?, locale: Locale, showsReset: Bool = false) -> [WidgetViewState.BarParams] {
        (quotas ?? []).compactMap { quota in
            guard let total = quota.total, total > 0, let used = quota.used else { return nil }
            let fraction = Double(truncating: (used / total) as NSDecimalNumber)
            let valueText = fraction.formatted(.percent.precision(.fractionLength(1)).locale(locale))
            return WidgetViewState.BarParams(
                kind: .quota,
                valueText: valueText,
                fraction: fraction,
                caption: quotaCaption(for: quota, locale: locale),
                resetText: showsReset ? quotaResetText(for: quota, locale: locale) : nil
            )
        }
    }

    /// Caption of a quota bar; `nil` falls back to the generic «Quota» label.
    private static func quotaCaption(for quota: Quota, locale: Locale) -> String? {
        switch quota.id {
        case KimiAdapter.codingMonthQuotaID:
            return String(localized: "widget.quota.month", bundle: .module, locale: locale)
        case KimiAdapter.codingQuotaID:
            return String(localized: "widget.quota.5h", bundle: .module, locale: locale)
        case MiMoAdapter.quotaID:
            return String(localized: "widget.quota.tokenPlan", bundle: .module, locale: locale)
        default:
            return nil
        }
    }

    /// Reset hint of a quota bar: the 5-hour window resets within the day (time),
    /// the monthly cap resets on a date.
    private static func quotaResetText(for quota: Quota, locale: Locale) -> String? {
        let reset: String?
        switch quota.id {
        case KimiAdapter.codingMonthQuotaID:
            reset = quota.resetsAt?.formatted(.dateTime.day().month().locale(locale))
        case KimiAdapter.codingQuotaID:
            reset = quota.period?.end.formatted(.dateTime.hour().minute().locale(locale))
        case MiMoAdapter.quotaID:
            reset = quota.period?.end.formatted(.dateTime.day().month().locale(locale))
        default:
            reset = nil
        }
        guard let reset else {
            return nil
        }
        return String(localized: "widget.until \(reset)", bundle: .module, locale: locale)
    }
}
