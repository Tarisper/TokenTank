import Foundation
import Testing
@testable import TokenTankKit
import TokenTankWidgetUI

struct ViewStateTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func account(displayCurrency: String? = nil, thresholds: [Threshold] = []) -> AccountDescriptor {
        AccountDescriptor(
            id: UUID(),
            provider: .deepseek,
            region: nil,
            label: "Test",
            credentialSlots: [],
            tier: nil,
            thresholds: thresholds,
            budgets: [],
            displayCurrency: displayCurrency
        )
    }

    private func snapshot(
        updatedAt: Date,
        balances: [Money]? = nil,
        quotas: [Quota]? = nil,
        history: [BalancePoint]? = nil,
        sections: [SectionSnapshot] = []
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountID: UUID(),
            updatedAt: updatedAt,
            isAvailable: true,
            balances: balances,
            quotas: quotas,
            usageHistory: nil,
            balanceHistory: history,
            limits: nil,
            modelTopByScope: nil,
            sections: sections
        )
    }

    private func history(from start: Decimal, days: Int) -> [BalancePoint] {
        (0..<days).map { index in
            BalancePoint(
                localDay: String(format: "2026-11-%02d", index + 1),
                timeZoneID: "UTC",
                available: start - Decimal(index),
                currency: "CNY"
            )
        }
    }

    @Test func displayCurrencyPrefersExplicitSetting() {
        let snapshot = snapshot(
            updatedAt: now,
            balances: [Money(role: .available, amount: 1, currency: "CNY")]
        )
        let result = ViewStateBuilder.displayCurrency(of: account(displayCurrency: "USD"), snapshot: snapshot)
        #expect(result == "USD")
    }

    @Test func displayCurrencyFallsBackToFirstAvailable() {
        let snapshot = snapshot(
            updatedAt: now,
            balances: [
                Money(role: .cash, amount: 5, currency: "USD"),
                Money(role: .available, amount: 1, currency: "CNY"),
            ]
        )
        #expect(ViewStateBuilder.displayCurrency(of: account(), snapshot: snapshot) == "CNY")
    }

    @Test func balanceTextListsAllCurrenciesWithDisplayFirst() {
        let snapshot = snapshot(
            updatedAt: now,
            balances: [
                Money(role: .available, amount: 10, currency: "CNY"),
                Money(role: .available, amount: 20, currency: "USD"),
            ]
        )
        let locale = Locale(identifier: "en_US")
        let text = ViewStateBuilder.balanceText(of: account(displayCurrency: "USD"), snapshot: snapshot, locale: locale)
        let usd = Decimal(20).formatted(.currency(code: "USD").locale(locale))
        let cny = Decimal(10).formatted(.currency(code: "CNY").locale(locale))
        #expect(text == "\(usd) · \(cny)")
    }

    @Test func smallKeepsEachCurrencyAsASeparateFormattedAmount() {
        let account = account(displayCurrency: "USD")
        let balances = [
            Money(role: .available, amount: 4.09, currency: "CNY"),
            Money(role: .available, amount: 0.17, currency: "USD"),
            Money(role: .cash, amount: 3, currency: "CNY"),
        ]
        let locale = Locale(identifier: "ru")
        let expected = [
            Decimal(string: "0.17")!.formatted(.currency(code: "USD").locale(locale)),
            Decimal(string: "4.09")!.formatted(.currency(code: "CNY").locale(locale)),
        ]
        let stored = snapshot(updatedAt: now, balances: balances)
        let passive = ViewStateBuilder.small(account: account, snapshot: stored, now: now, locale: locale)
        let primary = PrimarySnapshot(scope: .account, fetchedAt: now, balances: balances, quota: nil)
        let active = ViewStateBuilder.small(account: account, primary: primary, locale: locale)
        let failed = ViewStateBuilder.small(account: account, primaryResult: .failure(.invalidKey), snapshot: stored, now: now, locale: locale)
        #expect(passive.balanceTexts == expected)
        #expect(active.balanceTexts == expected)
        #expect(failed.state.balanceTexts == expected)
        #expect(passive.balanceText == expected.joined(separator: " · "))
    }

    @Test func quotaOnlyRowUsesTheSameStatusAsTheFocusedQuotaWidget() {
        let account = testAccount(provider: .kimi, region: .intl, slots: [
            CredentialSlot(id: "coding", kind: .coding, keychainRef: "ref-coding", baseURLOverride: nil),
        ])
        let quota = Quota(id: KimiAdapter.codingMonthQuotaID, kind: .subscription, unit: .percent, total: 100, used: 78.7, remaining: 21.3, period: nil, autoRenew: nil)
        let stored = snapshot(updatedAt: now, quotas: [quota], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.invalidKey), lastSuccessAt: nil, lastAttemptAt: now),
            SectionSnapshot(kind: .quotas, slotID: "coding", status: .ok, lastSuccessAt: now, lastAttemptAt: now),
        ])
        let list = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: stored], now: now)
        let focused = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: stored], focusAccountID: account.id, now: now)
        #expect(list.rows.first?.status == .ok)
        #expect(list.rows.first?.status == focused.focus?.status)
        #expect(list.rows.first?.statusText == nil)
        #expect(list.rows.first?.balanceText == ViewStateBuilder.limitsText(of: account, snapshot: stored))
    }

    @Test(arguments: [SectionKind.balance, .quotas])
    func rowStillReportsCredentialFailuresOfDisplayedMetrics(failedKind: SectionKind) {
        let account = account()
        let quota = Quota(id: "q", kind: .tokenPlan, unit: .credits, total: 100, used: 20, remaining: 80, period: nil, autoRenew: nil)
        let stored = snapshot(updatedAt: now, balances: [Money(role: .available, amount: 10, currency: "USD")], quotas: [quota], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: failedKind == .balance ? .failed(.invalidKey) : .ok, lastSuccessAt: now, lastAttemptAt: now),
            SectionSnapshot(kind: .quotas, slotID: "tp", status: failedKind == .quotas ? .failed(.invalidKey) : .ok, lastSuccessAt: now, lastAttemptAt: now),
        ])
        let list = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: stored], now: now)
        #expect(list.rows.first?.status == .error)
        #expect(list.rows.first?.statusText != nil)
    }

    @Test func rowWithoutDataStillReportsInvalidKey() {
        let account = account()
        let stored = snapshot(updatedAt: now, sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.invalidKey), lastSuccessAt: nil, lastAttemptAt: now),
            SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        let list = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: stored], now: now)
        #expect(list.rows.first?.status == .error)
        #expect(list.rows.first?.balanceText == "—")
    }

    @Test func priorityErrorWinsOverEverything() {
        let failed = SectionSnapshot(kind: .balance, slotID: nil, status: .failed(.network(code: -1)), lastSuccessAt: nil, lastAttemptAt: now)
        let snapshot = snapshot(updatedAt: now.addingTimeInterval(-7200), balances: [], sections: [failed])
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: Locale(identifier: "en_US"))
        #expect(state.status == .error)
        #expect(state.statusText != nil)
    }

    @Test func errorStatusTextIsLocalized() {
        let failed = SectionSnapshot(kind: .balance, slotID: nil, status: .failed(.server(status: 500)), lastSuccessAt: nil, lastAttemptAt: now)
        let snapshot = snapshot(updatedAt: now.addingTimeInterval(-60), balances: [], sections: [failed])
        let en = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: Locale(identifier: "en_US"))
        // The raw Swift description (`server(status: 500)`) must never reach the UI.
        #expect(en.statusText == "error: HTTP 500")
    }

    @Test func staleBeatsLowAndCombinesText() throws {
        let threshold = try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 500, rearmFraction: 1.1)
        let snapshot = snapshot(
            updatedAt: now.addingTimeInterval(-7200),
            balances: [Money(role: .available, amount: 100, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: nil, status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)]
        )
        let state = ViewStateBuilder.small(
            account: account(thresholds: [threshold]),
            snapshot: snapshot,
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.status == .stale)
        #expect(state.statusText?.contains("·") == true)
    }

    @Test func lowShowsStatusText() throws {
        let threshold = try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 500, rearmFraction: 1.1)
        let snapshot = snapshot(
            updatedAt: now.addingTimeInterval(-60),
            balances: [Money(role: .available, amount: 100, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: nil, status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)]
        )
        let state = ViewStateBuilder.small(
            account: account(thresholds: [threshold]),
            snapshot: snapshot,
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.status == .low)
        #expect(state.statusText == "low balance")
    }

    @Test func okHasNoStatusText() {
        let snapshot = snapshot(
            updatedAt: now.addingTimeInterval(-60),
            balances: [Money(role: .available, amount: 100, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: nil, status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)]
        )
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: Locale(identifier: "en_US"))
        #expect(state.status == .ok)
        #expect(state.statusText == nil)
    }

    @Test func missingSnapshotIsEmpty() {
        let state = ViewStateBuilder.small(account: account(), snapshot: nil, now: now, locale: Locale(identifier: "en_US"))
        #expect(state.status == .empty)
    }

    @Test func quotaDrivesTheRing() {
        let quota = Quota(
            id: "q",
            kind: .tokenPlan,
            unit: .credits,
            total: 1000,
            used: 328,
            remaining: 672,
            period: nil,
            autoRenew: nil
        )
        let snapshot = snapshot(updatedAt: now, quotas: [quota])
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: Locale(identifier: "en_US"))
        guard case .ring(_, let centerText, _) = state.display else {
            Issue.record("expected ring")
            return
        }
        #expect(centerText == "33%")
    }

    @Test func forecastDrivesTheRingAndRowPhrase() {
        let snapshot = snapshot(updatedAt: now, history: history(from: 25, days: 4))
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: Locale(identifier: "en_US"))
        guard case .ring(_, let centerText, _) = state.display else {
            Issue.record("expected ring")
            return
        }
        #expect(centerText == "22")

        let account = account()
        let medium = ViewStateBuilder.medium(
            accounts: [account],
            snapshots: [account.id: snapshot],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(medium.rows.first?.detailText == "≈ 22 days left")
        // The account list has no single update time; only a focused account has one.
        #expect(medium.updatedAtText == nil)
    }

    @Test func pluralVariantsResolvePerCount() {
        for (count, expected) in [
            (1, "≈ 1 day left"),
            (2, "≈ 2 days left"),
            (5, "≈ 5 days left"),
            (22, "≈ 22 days left"),
        ] {
            let snapshot = snapshot(updatedAt: now, history: history(from: Decimal(count + 3), days: 4))
            let account = account()
            let medium = ViewStateBuilder.medium(
                accounts: [account],
                snapshots: [account.id: snapshot],
                now: now,
                locale: Locale(identifier: "en_US")
            )
            #expect(medium.rows.first?.detailText == expected)
        }
    }

    @Test func catalogDefinesRussianPluralForms() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TokenTankWidgetUI/Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
        let entry = catalog.strings["widget.daysRemaining %lld"]
        let ruPlural = entry?.localizations?["ru"]?.variations?.plural
        #expect(ruPlural?["one"]?.stringUnit.value.hasSuffix("день") == true)
        #expect(ruPlural?["few"]?.stringUnit.value.hasSuffix("дня") == true)
        #expect(ruPlural?["many"]?.stringUnit.value.hasSuffix("дней") == true)
        #expect(ruPlural?["one"]?.stringUnit.value.contains("%lld") == true)
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Variations: Decodable {
                    struct Form: Decodable {
                        struct StringUnit: Decodable {
                            let value: String
                        }
                        let stringUnit: StringUnit
                    }
                    let plural: [String: Form]?
                }
                let variations: Variations?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    @Test func noDataWithoutForecastOrQuota() {
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot(updatedAt: now), now: now, locale: Locale(identifier: "en_US"))
        guard case .noData = state.display else {
            Issue.record("expected noData")
            return
        }
    }

    private func snapshotWithUsage(
        status: FetchStatus,
        usages: [ModelUsage]?,
        updatedAt: Date
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountID: UUID(),
            updatedAt: updatedAt,
            isAvailable: true,
            balances: nil,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: usages.map { [Scope.account.rawValue: $0] },
            sections: [SectionSnapshot(kind: .usage, slotID: "sk", status: status, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
    }

    private func usage(_ model: String, cost: Decimal?, tokens: Int?, share: Decimal? = nil) -> ModelUsage {
        ModelUsage(
            model: model,
            requests: 1,
            tokens: tokens,
            cost: cost.map { Money(role: .cash, amount: $0, currency: "CNY") },
            share: share
        )
    }

    @Test func topModelsStatesFollowSectionAndData() throws {
        let locale = Locale(identifier: "en_US")
        let account = account()

        let unsupported = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(status: .unsupported, usages: nil, updatedAt: now),
            scope: .account,
            now: now,
            locale: locale
        )
        #expect(unsupported.status == .unsupported)

        let failed = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(status: .failed(.invalidKey), usages: nil, updatedAt: now),
            scope: .account,
            now: now,
            locale: locale
        )
        #expect(failed.status == .error)

        let noData = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(status: .ok, usages: [], updatedAt: now),
            scope: .account,
            now: now,
            locale: locale
        )
        #expect(noData.status == .noData)

        let zeroSpend = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(status: .ok, usages: [usage("m", cost: 0, tokens: 0)], updatedAt: now),
            scope: .account,
            now: now,
            locale: locale
        )
        #expect(zeroSpend.status == .zeroSpend)

        let ok = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(status: .ok, usages: [usage("m", cost: 10, tokens: 5)], updatedAt: now),
            scope: .account,
            now: now,
            locale: locale
        )
        #expect(ok.status == .ok)
        #expect(ok.rows.count == 1)
    }

    @Test func topModelsBarUsesScopeTotalDenominator() {
        var account = account()
        account.budgets = [AccountBudget(currency: "CNY", amount: 100)]
        let state = ViewStateBuilder.topModels(
            account: account,
            snapshot: snapshotWithUsage(
                status: .ok,
                usages: [usage("m", cost: 40, tokens: 5)],
                updatedAt: now
            ),
            scope: .account,
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.rows.first?.valueText == "40 / 100 CNY")
        #expect(state.rows.first?.fraction == 0.4)
    }

    @Test func topModelsWithoutBudgetShowSharesWithoutBars() {
        let state = ViewStateBuilder.topModels(
            account: account(),
            snapshot: snapshotWithUsage(
                status: .ok,
                usages: [usage("a", cost: 30, tokens: 1, share: 0.75), usage("b", cost: 10, tokens: 1, share: 0.25)],
                updatedAt: now
            ),
            scope: .account,
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.rows.allSatisfy { $0.fraction == nil })
        #expect(state.rows.first?.valueText == "75%")
    }

    @Test func quotaScopeRowsAreBarlessUntilProbe() throws {
        let quota = Quota(id: "mimo.tokenplan", kind: .tokenPlan, unit: .credits, total: 1000, used: 1, remaining: 999, period: nil, autoRenew: nil)
        var snap = snapshotWithUsage(status: .ok, usages: [usage("m", cost: nil, tokens: 77)], updatedAt: now)
        snap = AccountSnapshot(
            accountID: snap.accountID,
            updatedAt: snap.updatedAt,
            isAvailable: true,
            balances: nil,
            quotas: [quota],
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: [Scope.quota(quota.id).rawValue: [usage("m", cost: nil, tokens: 77)]],
            sections: snap.sections
        )
        let state = ViewStateBuilder.topModels(
            account: account(),
            snapshot: snap,
            scope: .quota(quota.id),
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.rows.count == 1)
        #expect(state.rows.first?.fraction == nil)
    }

    @Test func activeModeMapsCredentialFailureToErrorState() {
        let account = account()
        let result = ViewStateBuilder.small(
            account: account,
            primaryResult: .failure(.invalidKey),
            snapshot: snapshot(updatedAt: now.addingTimeInterval(-60), balances: [Money(role: .available, amount: 1, currency: "CNY")]),
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(result.state.status == .error)
        #expect(result.activeFailed == false)
    }

    @Test func activeModeMapsTransientFailureToIndicator() {
        let account = account()
        let result = ViewStateBuilder.small(
            account: account,
            primaryResult: .failure(.network(code: -1009)),
            snapshot: nil,
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(result.activeFailed == true)
    }

    @Test func mediumFocusShowsQuotaBarsWithResets() {
        let locale = Locale(identifier: "en_US")
        let account = account()
        let month = Quota(
            id: KimiAdapter.codingMonthQuotaID,
            kind: .subscription,
            unit: .percent,
            total: 100,
            used: Decimal(string: "78.5"),
            remaining: Decimal(string: "21.5"),
            period: nil,
            autoRenew: nil,
            resetsAt: now.addingTimeInterval(10 * 86_400)
        )
        let fiveHour = Quota(
            id: KimiAdapter.codingQuotaID,
            kind: .subscription,
            unit: .percent,
            total: 100,
            used: Decimal(string: "13.4"),
            remaining: Decimal(string: "86.6"),
            period: Period(start: now, end: now.addingTimeInterval(5 * 3600)),
            autoRenew: nil
        )
        let state = ViewStateBuilder.medium(
            accounts: [account],
            snapshots: [account.id: snapshot(updatedAt: now, quotas: [month, fiveHour])],
            focusAccountID: account.id,
            now: now,
            locale: locale
        )
        guard let focus = state.focus else {
            Issue.record("expected the focused account")
            return
        }
        #expect(focus.label == account.label)
        #expect(focus.bars.count == 2)
        #expect(focus.bars.first?.caption == "Month")
        #expect(focus.bars.first?.valueText == (0.785).formatted(.percent.precision(.fractionLength(1)).locale(locale)))
        #expect(focus.bars.first?.resetText?.hasPrefix("until ") == true)
        #expect(focus.bars.last?.caption == "5 hours")
        #expect(focus.bars.last?.resetText?.hasPrefix("until ") == true)
        #expect(state.updatedAtText != nil)
    }

    @Test func limitsTextShowsKimiSharesAndFiveHourReset() {
        let locale = Locale(identifier: "en_US")
        let fiveHourReset = now.addingTimeInterval(5 * 3600)
        let month = Quota(
            id: KimiAdapter.codingMonthQuotaID,
            kind: .subscription,
            unit: .percent,
            total: 100,
            used: 78.7,
            remaining: 21.3,
            period: nil,
            autoRenew: nil
        )
        let fiveHour = Quota(
            id: KimiAdapter.codingQuotaID,
            kind: .subscription,
            unit: .percent,
            total: 100,
            used: 13.4,
            remaining: 86.6,
            period: Period(start: now, end: fiveHourReset),
            autoRenew: nil
        )
        let text = ViewStateBuilder.limitsText(
            of: account(),
            snapshot: snapshot(updatedAt: now, quotas: [month, fiveHour]),
            locale: locale
        )
        let reset = fiveHourReset.formatted(.dateTime.hour().minute().locale(locale))
        #expect(text == "78.7%/13% \(reset)")
    }

    @Test func limitsTextShowsSingleQuotaShare() {
        let quota = Quota(
            id: MiMoAdapter.quotaID,
            kind: .tokenPlan,
            unit: .credits,
            total: 1000,
            used: 328,
            remaining: 672,
            period: nil,
            autoRenew: nil
        )
        let text = ViewStateBuilder.limitsText(
            of: account(),
            snapshot: snapshot(updatedAt: now, quotas: [quota]),
            locale: Locale(identifier: "en_US")
        )
        #expect(text == "32.8%")
    }

    @Test func mediumRowsCarryLimitsForQuotaAccounts() {
        let kimi = account()
        let month = Quota(id: KimiAdapter.codingMonthQuotaID, kind: .subscription, unit: .percent, total: 100, used: 78.7, remaining: 21.3, period: nil, autoRenew: nil)
        let fiveHour = Quota(id: KimiAdapter.codingQuotaID, kind: .subscription, unit: .percent, total: 100, used: 13.4, remaining: 86.6, period: Period(start: now, end: now.addingTimeInterval(3600)), autoRenew: nil)
        let state = ViewStateBuilder.medium(
            accounts: [kimi],
            snapshots: [kimi.id: snapshot(updatedAt: now, quotas: [month, fiveHour])],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        guard let row = state.rows.first else {
            Issue.record("expected a row")
            return
        }
        #expect(row.balanceText.hasPrefix("78.7%/13%"))
    }

    @Test func mediumRowsJoinBalanceAndLimitsInOneLine() {
        let account = account()
        let quota = Quota(
            id: MiMoAdapter.quotaID,
            kind: .tokenPlan,
            unit: .credits,
            total: 1000,
            used: 328,
            remaining: 672,
            period: nil,
            autoRenew: nil
        )
        let state = ViewStateBuilder.medium(
            accounts: [account],
            snapshots: [
                account.id: snapshot(
                    updatedAt: now,
                    balances: [Money(role: .available, amount: 0, currency: "USD")],
                    quotas: [quota]
                ),
            ],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(state.rows.first?.balanceText == "$0.00 · 32.8%")
    }

    @Test func realAdapterCredentialFailureBeatsUnsupportedSections() async throws {
        let account = testAccount(provider: .deepseek)
        let snapshot = try await DeepSeekAdapter(descriptor: account, keychain: InMemoryKeychain()).fetchAccount()
        let state = ViewStateBuilder.small(account: account, snapshot: snapshot, now: snapshot.updatedAt, locale: Locale(identifier: "en_US"))
        #expect(state.status == .error)
        #expect(state.statusText?.contains("key") == true)
        #expect(state.updatedAtText == nil)
    }

    @Test func usageSuccessDoesNotRefreshOldBalanceTime() {
        let old = now.addingTimeInterval(-7200)
        let snapshot = snapshot(updatedAt: now, balances: [Money(role: .available, amount: 100, currency: "CNY")], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.network(code: -1009)), lastSuccessAt: old, lastAttemptAt: now),
            SectionSnapshot(kind: .usage, slotID: "sk", status: .ok, lastSuccessAt: now, lastAttemptAt: now),
            SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        let locale = Locale(identifier: "en_US")
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: locale)
        #expect(state.status == .error)
        #expect(ViewStateBuilder.dataUpdatedAt(of: snapshot) == old)
        #expect(state.updatedAtText?.contains(old.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))) == true)
    }

    @Test func freshBalanceDoesNotHideStaleQuota() {
        let old = now.addingTimeInterval(-7200)
        let quota = Quota(id: "q", kind: .tokenPlan, unit: .credits, total: 100, used: 20, remaining: 80, period: nil, autoRenew: nil)
        let snapshot = snapshot(updatedAt: now, balances: [Money(role: .available, amount: 100, currency: "CNY")], quotas: [quota], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: now, lastAttemptAt: now),
            SectionSnapshot(kind: .quotas, slotID: "tp", status: .failed(.network(code: -1009)), lastSuccessAt: old, lastAttemptAt: now),
        ])
        let state = ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now)
        #expect(state.status == .stale)
        #expect(ViewStateBuilder.dataUpdatedAt(of: snapshot) == old)
    }

    @Test func stalenessStartsAtTheTimelineBoundary() {
        let snapshot = snapshot(updatedAt: now.addingTimeInterval(-ViewStateBuilder.staleness), balances: [Money(role: .available, amount: 100, currency: "CNY")])
        #expect(ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now).status == .stale)
    }

    @Test func primaryBalanceUpdatesMediumRowsWithoutChangingStoredData() {
        let account = account()
        let stored = snapshot(updatedAt: now.addingTimeInterval(-3600), balances: [Money(role: .available, amount: 100, currency: "CNY")])
        let primary = PrimarySnapshot(scope: .account, fetchedAt: now, balances: [Money(role: .available, amount: 1, currency: "CNY")], quota: nil)
        let display = AccountSnapshot(account: account, primaryResult: .success(primary), scope: .account, previous: stored, now: now)
        let locale = Locale(identifier: "en_US")
        let medium = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: display], now: now, locale: locale)
        #expect(medium.rows.first?.balanceText == Decimal(1).formatted(.currency(code: "CNY").locale(locale)))
        #expect(medium.rows.first?.status == .ok)
        #expect(stored.balances?.first?.amount == 100)
        #expect(display.sections.first { $0.kind == .balance }?.lastSuccessAt == now)
    }

    @Test func activeBalanceIsVisibleWhenTheAccountAlsoHasQuotas() {
        let account = account()
        let quota = Quota(id: "q", kind: .tokenPlan, unit: .credits, total: 100, used: 20, remaining: 80, period: nil, autoRenew: nil)
        let stored = snapshot(updatedAt: now, balances: [Money(role: .available, amount: 100, currency: "CNY")], quotas: [quota])
        let primary = PrimarySnapshot(scope: .account, fetchedAt: now, balances: [Money(role: .available, amount: 1, currency: "CNY")], quota: nil)
        let display = AccountSnapshot(account: account, primaryResult: .success(primary), scope: .account, previous: stored, now: now)
        let locale = Locale(identifier: "en_US")
        let medium = ViewStateBuilder.medium(
            accounts: [account], snapshots: [account.id: display], focusAccountID: account.id,
            primaryScope: primary.scope, now: now, locale: locale
        )
        #expect(medium.focus == nil)
        #expect(medium.rows.first?.balanceText.hasPrefix(Decimal(1).formatted(.currency(code: "CNY").locale(locale))) == true)
    }

    @Test func primaryQuotaUpdatesMediumFocusAndPreservesOtherQuotas() throws {
        let account = account()
        let old = now.addingTimeInterval(-3600)
        let quota = Quota(id: "q", kind: .tokenPlan, unit: .credits, total: 100, used: 20, remaining: 80, period: nil, autoRenew: nil)
        let other = Quota(id: "other", kind: .subscription, unit: .requests, total: 100, used: 10, remaining: 90, period: nil, autoRenew: nil)
        let stored = snapshot(updatedAt: old, quotas: [quota, other], sections: [
            SectionSnapshot(kind: .quotas, slotID: "tp", status: .ok, lastSuccessAt: old, lastAttemptAt: old),
        ])
        let updated = Quota(id: "q", kind: .tokenPlan, unit: .credits, total: 100, used: 90, remaining: 10, period: nil, autoRenew: nil)
        let primary = PrimarySnapshot(scope: .quota("q"), fetchedAt: now, balances: nil, quota: updated)
        let display = AccountSnapshot(account: account, primaryResult: .success(primary), scope: .account, previous: stored, now: now)
        let medium = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: display], focusAccountID: account.id, now: now)
        let focus = try #require(medium.focus)
        #expect(focus.bars.map(\.fraction) == [0.9, 0.1])
        #expect(display.quotas?.last == other)
        #expect(stored.quotas?.first == quota)
        #expect(ViewStateBuilder.dataUpdatedAt(of: display, kinds: [.quotas]) == old)
    }

    @Test func primaryCredentialFailureReachesMediumFocus() {
        let account = testAccount(provider: .mimo, slots: [CredentialSlot(id: "tp", kind: .tokenPlan, keychainRef: "ref", baseURLOverride: nil)])
        let quota = Quota(id: MiMoAdapter.quotaID, kind: .tokenPlan, unit: .credits, total: 100, used: 20, remaining: 80, period: nil, autoRenew: nil)
        let stored = snapshot(updatedAt: now.addingTimeInterval(-60), quotas: [quota])
        let display = AccountSnapshot(account: account, primaryResult: .failure(.invalidKey), scope: .account, previous: stored, now: now)
        let medium = ViewStateBuilder.medium(accounts: [account], snapshots: [account.id: display], focusAccountID: account.id, now: now)
        #expect(medium.focus?.status == .error)
        #expect(medium.focus?.bars.first?.fraction == 0.2)
        #expect(display.quotas == stored.quotas)
    }

    @Test(arguments: [true, false])
    func topModelSharesIncludeModelsOutsideTheTopThree(monetary: Bool) throws {
        let models = ["a", "b", "c", "d"].map { usage($0, cost: monetary ? 25 : nil, tokens: 100) }
        let history = [DailyUsage(localDay: "2026-11-14", timeZoneID: "UTC", requests: nil, tokensIn: nil, tokensOut: nil, cost: nil, models: models)]
        let top = TopModels.aggregate(history: history)
        let saved = try JSONDecoder().decode([ModelUsage].self, from: JSONEncoder().encode(top))
        let state = ViewStateBuilder.topModels(
            account: account(), snapshot: snapshotWithUsage(status: .ok, usages: saved, updatedAt: now),
            scope: .account, now: now, locale: Locale(identifier: "en_US")
        )
        #expect(state.rows.count == 3)
        #expect(state.rows.map(\.valueText) == ["25%", "25%", "25%"])
    }

    @Test func legacyModelUsageDoesNotInventShares() throws {
        let json = Data(#"{"model":"legacy","requests":1,"tokens":100,"cost":{"role":"cash","amount":25,"currency":"CNY"}}"#.utf8)
        let legacy = try JSONDecoder().decode(ModelUsage.self, from: json)
        #expect(legacy.share == nil)
        let locale = Locale(identifier: "en_US")
        let state = ViewStateBuilder.topModels(
            account: account(), snapshot: snapshotWithUsage(status: .ok, usages: [legacy], updatedAt: now),
            scope: .account, now: now, locale: locale
        )
        #expect(state.rows.first?.valueText == Decimal(25).formatted(.currency(code: "CNY").locale(locale)))
    }
}
