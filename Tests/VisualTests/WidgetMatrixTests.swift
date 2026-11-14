import Foundation
import SwiftUI
import Testing
@testable import TokenTankKit
@testable import TokenTankWidgetUI

/// Fixture states for rendering (mirror the dark/light mockups, §8.4).
@MainActor
enum RenderFixtures {
    static let now = Date(timeIntervalSince1970: 2_000_000)
    static let smallSize = CGSize(width: 155, height: 155)
    static let mediumSize = CGSize(width: 329, height: 155)

    static func account(label: String = "DeepSeek", thresholds: [Threshold] = []) -> AccountDescriptor {
        let id = label == "MiMo"
            ? UUID(uuidString: "6F1E4B2C-8A44-4A0B-9E67-1B7A3F0D2C12")!
            : UUID(uuidString: "6F1E4B2C-8A44-4A0B-9E67-1B7A3F0D2C11")!
        return AccountDescriptor(
            id: id,
            provider: .deepseek,
            region: nil,
            label: label,
            credentialSlots: [],
            tier: nil,
            thresholds: thresholds,
            budgets: [AccountBudget(currency: "CNY", amount: 100)],
            displayCurrency: nil
        )
    }

    static func deepseekSnapshot(updatedAt: Date) -> AccountSnapshot {
        AccountSnapshot(
            accountID: account().id,
            updatedAt: updatedAt,
            isAvailable: true,
            balances: [
                Money(role: .available, amount: Decimal(string: "110.00")!, currency: "CNY"),
                Money(role: .granted, amount: Decimal(string: "10.00")!, currency: "CNY"),
                Money(role: .toppedUp, amount: Decimal(string: "100.00")!, currency: "CNY"),
            ],
            quotas: nil,
            usageHistory: nil,
            balanceHistory: (0..<4).map {
                BalancePoint(
                    localDay: String(format: "2026-11-%02d", $0 + 1),
                    timeZoneID: "UTC",
                    available: Decimal(25 - $0),
                    currency: "CNY"
                )
            },
            limits: nil,
            modelTopByScope: [
                Scope.account.rawValue: [
                    ModelUsage(model: "mimo-v2.6-pro", requests: 10, tokens: 1000, cost: Money(role: .cash, amount: 40, currency: "CNY")),
                    ModelUsage(model: "mimo-v2.6-flash", requests: 20, tokens: 2000, cost: Money(role: .cash, amount: 25, currency: "CNY")),
                    ModelUsage(model: "mimo-v2.5-asr", requests: 2, tokens: 300, cost: Money(role: .cash, amount: 10, currency: "CNY")),
                ]
            ],
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
    }

    static func mimoSnapshot(updatedAt: Date) -> AccountSnapshot {
        AccountSnapshot(
            accountID: account(label: "MiMo").id,
            updatedAt: updatedAt,
            isAvailable: true,
            balances: [Money(role: .available, amount: Decimal(string: "57.30")!, currency: "CNY")],
            quotas: [
                Quota(
                    id: "mimo.tokenplan",
                    kind: .tokenPlan,
                    unit: .credits,
                    total: 1000,
                    used: 328,
                    remaining: 672,
                    period: Period(start: updatedAt, end: updatedAt.addingTimeInterval(30 * 86_400)),
                    autoRenew: true
                )
            ],
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
    }

    /// Two currencies with optional forecast history for the small widget width regression.
    static func multiCurrencySnapshot(updatedAt: Date, includeHistory: Bool) -> AccountSnapshot {
        AccountSnapshot(
            accountID: account().id,
            updatedAt: updatedAt,
            isAvailable: true,
            balances: [
                Money(role: .available, amount: Decimal(string: "0.17")!, currency: "USD"),
                Money(role: .available, amount: Decimal(string: "4.09")!, currency: "CNY"),
            ],
            quotas: nil,
            usageHistory: nil,
            balanceHistory: includeHistory ? (0..<4).map {
                BalancePoint(
                    localDay: String(format: "2026-11-%02d", $0 + 1),
                    timeZoneID: "UTC",
                    available: Decimal(20 - $0) / 100,
                    currency: "USD"
                )
            } : nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
    }

    static func kimiSnapshot(updatedAt: Date) -> AccountSnapshot {
        AccountSnapshot(
            accountID: account(label: "Kimi").id,
            updatedAt: updatedAt,
            isAvailable: nil,
            balances: nil,
            quotas: [
                Quota(
                    id: "kimi.coding.month",
                    kind: .subscription,
                    unit: .percent,
                    total: 100,
                    used: Decimal(string: "78.5"),
                    remaining: Decimal(string: "21.5"),
                    period: nil,
                    autoRenew: nil,
                    resetsAt: updatedAt.addingTimeInterval(10 * 86_400)
                ),
                Quota(
                    id: "kimi.coding",
                    kind: .subscription,
                    unit: .percent,
                    total: 100,
                    used: Decimal(string: "13.4"),
                    remaining: Decimal(string: "86.6"),
                    period: Period(start: updatedAt, end: updatedAt.addingTimeInterval(5 * 3600)),
                    autoRenew: nil
                ),
            ],
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .quotas, slotID: "coding", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
    }

    static func smallState(
        snapshot: AccountSnapshot?,
        locale: Locale,
        now: Date = RenderFixtures.now
    ) -> WidgetViewState.Small {
        ViewStateBuilder.small(account: account(), snapshot: snapshot, now: now, locale: locale)
    }

    static func mediumState(locale: Locale, now: Date = RenderFixtures.now) -> WidgetViewState.Medium {
        let deepseek = account()
        let mimo = account(label: "MiMo")
        return ViewStateBuilder.medium(
            accounts: [deepseek, mimo],
            snapshots: [
                deepseek.id: deepseekSnapshot(updatedAt: now),
                mimo.id: mimoSnapshot(updatedAt: now),
            ],
            now: now,
            locale: locale
        )
    }

    static func topModelsState(locale: Locale, updatedAt: Date? = nil) -> WidgetViewState.TopModels {
        let updatedAt = updatedAt ?? now
        let snapshot = AccountSnapshot(
            accountID: account(label: "MiMo").id,
            updatedAt: updatedAt,
            isAvailable: true,
            balances: nil,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: deepseekSnapshot(updatedAt: now).modelTopByScope,
            sections: [SectionSnapshot(kind: .usage, slotID: "sk", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
        )
        return ViewStateBuilder.topModels(
            account: account(label: "MiMo"),
            snapshot: snapshot,
            scope: .account,
            now: now,
            locale: locale
        )
    }
}

/// Appearance × wallpaper matrix per layout (shortened per the M3.1 spike —
/// see Tests/VisualTests/README.md) and en/ru locale snapshots.
@MainActor
struct WidgetMatrixTests {
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
    private static let wallpapers: [RenderHarness.Wallpaper] = [.white, .dark, .colorful]

    @Test func smallLayoutsMatrix() throws {
        for (layoutName, layout) in [("ring", SmallLayout.ring), ("bars", SmallLayout.bars), ("rows", SmallLayout.rows)] {
            for (schemeName, scheme) in Self.schemes {
                for wallpaper in Self.wallpapers {
                    let state = RenderFixtures.smallState(
                        snapshot: RenderFixtures.deepseekSnapshot(updatedAt: RenderFixtures.now),
                        locale: Locale(identifier: "en_US")
                    )
                    try RenderHarness.verify(
                        name: "small-\(layoutName)-\(schemeName)-\(wallpaper.rawValue)",
                        view: SmallLayoutView(state: state, layout: layout, activeFailed: false),
                        wallpaper: wallpaper,
                        colorScheme: scheme,
                        size: RenderFixtures.smallSize
                    )
                }
            }
        }
    }

    @Test func mediumMatrix() throws {
        for (schemeName, scheme) in Self.schemes {
            for wallpaper in Self.wallpapers {
                try RenderHarness.verify(
                    name: "medium-\(schemeName)-\(wallpaper.rawValue)",
                    view: MediumLayoutView(
                        state: RenderFixtures.mediumState(locale: Locale(identifier: "en_US")),
                        activeFailed: false
                    ),
                    wallpaper: wallpaper,
                    colorScheme: scheme,
                    size: RenderFixtures.mediumSize
                )
            }
        }
    }

    @Test func multiCurrencySmallLayouts() throws {
        for (schemeName, scheme) in Self.schemes {
            for includeHistory in [false, true] {
                let state = RenderFixtures.smallState(
                    snapshot: RenderFixtures.multiCurrencySnapshot(updatedAt: RenderFixtures.now, includeHistory: includeHistory),
                    locale: Locale(identifier: "ru")
                )
                for (name, layout) in [("ring", SmallLayout.ring), ("bars", .bars), ("rows", .rows)] {
                    try RenderHarness.verify(
                        name: "small-multicurrency-\(name)-\(schemeName)-history-\(includeHistory)",
                        view: SmallLayoutView(state: state, layout: layout, activeFailed: false)
                            .environment(\.locale, Locale(identifier: "ru")),
                        wallpaper: .white,
                        colorScheme: scheme,
                        size: RenderFixtures.smallSize
                    )
                }
            }
        }
    }

    @Test func mediumKimiFocusMatrix() throws {
        let account = RenderFixtures.account(label: "Kimi")
        let snapshot = RenderFixtures.kimiSnapshot(updatedAt: RenderFixtures.now)
        for (schemeName, scheme) in Self.schemes {
            let state = ViewStateBuilder.medium(
                accounts: [account],
                snapshots: [account.id: snapshot],
                focusAccountID: account.id,
                now: RenderFixtures.now,
                locale: Locale(identifier: "en_US")
            )
            try RenderHarness.verify(
                name: "medium-kimi-focus-\(schemeName)",
                view: MediumLayoutView(state: state, activeFailed: false),
                wallpaper: .white,
                colorScheme: scheme,
                size: RenderFixtures.mediumSize
            )
        }
    }

    @Test func kimiSmallFocus() throws {
        let account = RenderFixtures.account(label: "Kimi")
        let snapshot = RenderFixtures.kimiSnapshot(updatedAt: RenderFixtures.now)
        let state = ViewStateBuilder.medium(
            accounts: [account],
            snapshots: [account.id: snapshot],
            focusAccountID: account.id,
            now: RenderFixtures.now,
            locale: Locale(identifier: "en_US")
        )
        try RenderHarness.verify(
            name: "kimi-small-focus",
            view: MediumLayoutView(state: state, activeFailed: false, compact: true),
            wallpaper: .white,
            colorScheme: .light,
            size: RenderFixtures.smallSize
        )
    }

    @Test func mimoSmallFocus() throws {
        let account = RenderFixtures.account(label: "MiMo")
        let snapshot = RenderFixtures.mimoSnapshot(updatedAt: RenderFixtures.now)
        let state = ViewStateBuilder.medium(
            accounts: [account],
            snapshots: [account.id: snapshot],
            focusAccountID: account.id,
            now: RenderFixtures.now,
            locale: Locale(identifier: "en_US")
        )
        try RenderHarness.verify(
            name: "mimo-small-focus",
            view: MediumLayoutView(state: state, activeFailed: false, compact: true),
            wallpaper: .white,
            colorScheme: .light,
            size: RenderFixtures.smallSize
        )
    }

    @Test func topModelsMatrix() throws {
        for (schemeName, scheme) in Self.schemes {
            for wallpaper in Self.wallpapers {
                try RenderHarness.verify(
                    name: "topmodels-\(schemeName)-\(wallpaper.rawValue)",
                    view: TopModelsLayoutView(state: RenderFixtures.topModelsState(locale: Locale(identifier: "en_US"))),
                    wallpaper: wallpaper,
                    colorScheme: scheme,
                    size: RenderFixtures.mediumSize
                )
            }
        }
    }

    @Test func topModelsSmallMatrix() throws {
        for (schemeName, scheme) in Self.schemes {
            for locale in [Locale(identifier: "en_US"), Locale(identifier: "ru")] {
                for (status, updatedAt) in [("ok", RenderFixtures.now), ("stale", RenderFixtures.now.addingTimeInterval(-7200))] {
                    try RenderHarness.verify(
                        name: "topmodels-small-\(status)-\(schemeName)-\(locale.identifier)",
                        view: TopModelsLayoutView(state: RenderFixtures.topModelsState(locale: locale, updatedAt: updatedAt)),
                        wallpaper: .white,
                        colorScheme: scheme,
                        size: RenderFixtures.smallSize
                    )
                }
            }
        }
    }

    @Test func localeSnapshots() throws {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "ru")] {
            let suffix = locale.identifier == "ru" ? "ru" : "en"
            let state = RenderFixtures.smallState(
                snapshot: RenderFixtures.deepseekSnapshot(updatedAt: RenderFixtures.now),
                locale: locale
            )
            try RenderHarness.verify(
                name: "small-ring-dark-colorful-\(suffix)",
                view: SmallLayoutView(state: state, layout: .ring, activeFailed: false)
                    .environment(\.locale, locale),
                wallpaper: .colorful,
                colorScheme: .dark,
                size: RenderFixtures.smallSize
            )
            try RenderHarness.verify(
                name: "medium-dark-colorful-\(suffix)",
                view: MediumLayoutView(state: RenderFixtures.mediumState(locale: locale), activeFailed: false)
                    .environment(\.locale, locale),
                wallpaper: .colorful,
                colorScheme: .dark,
                size: RenderFixtures.mediumSize
            )
        }
    }

    /// Statuses must fit without truncation (M3 criterion): empty/ok/low/stale/error.
    @Test func statusVariants() throws {
        let lowThreshold = try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 15, rearmFraction: 1.1)
        var lowAccount = RenderFixtures.account(thresholds: [lowThreshold])
        lowAccount.label = "Kimi intl"
        let lowSnapshot = AccountSnapshot(
            accountID: lowAccount.id,
            updatedAt: RenderFixtures.now,
            isAvailable: true,
            balances: [Money(role: .available, amount: Decimal(string: "9.60")!, currency: "CNY")],
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: RenderFixtures.now, lastAttemptAt: RenderFixtures.now)]
        )
        let staleSnapshot = RenderFixtures.deepseekSnapshot(updatedAt: RenderFixtures.now.addingTimeInterval(-7200))
        let errorSnapshot = AccountSnapshot(
            accountID: RenderFixtures.account().id,
            updatedAt: RenderFixtures.now.addingTimeInterval(-7200),
            isAvailable: nil,
            balances: nil,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.network(code: -1009)), lastSuccessAt: nil, lastAttemptAt: RenderFixtures.now)]
        )
        let cases: [(String, AccountDescriptor, AccountSnapshot?)] = [
            ("empty", RenderFixtures.account(), nil),
            ("ok", RenderFixtures.account(), RenderFixtures.deepseekSnapshot(updatedAt: RenderFixtures.now)),
            ("low", lowAccount, lowSnapshot),
            ("stale", RenderFixtures.account(), staleSnapshot),
            ("error", RenderFixtures.account(), errorSnapshot),
        ]
        for (caseName, account, snapshot) in cases {
            for (schemeName, scheme) in Self.schemes {
                let state = ViewStateBuilder.small(
                    account: account,
                    snapshot: snapshot,
                    now: RenderFixtures.now,
                    locale: Locale(identifier: "en_US")
                )
                try RenderHarness.verify(
                    name: "small-status-\(caseName)-\(schemeName)",
                    view: SmallLayoutView(state: state, layout: .ring, activeFailed: caseName == "error"),
                    wallpaper: .dark,
                    colorScheme: scheme,
                    size: RenderFixtures.smallSize
                )
            }
        }
    }
}
