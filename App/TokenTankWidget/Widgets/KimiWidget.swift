import SwiftUI
import TokenTankKit
import TokenTankWidgetUI
import WidgetKit

/// Kimi Code widget: the account's quota bars (monthly cap and 5-hour window),
/// no configuration — the Kimi account is found by provider.
struct KimiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KimiWidget", provider: ProviderWidgetTimelineProvider(provider: .kimi)) { entry in
            MediumLayoutView(state: entry.medium, activeFailed: entry.activeFailed)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.kimi"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemMedium])
    }
}

/// Small Kimi Code widget: the same quota bars in the small family.
struct KimiSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KimiSmallWidget", provider: ProviderWidgetTimelineProvider(provider: .kimi)) { entry in
            MediumLayoutView(state: entry.medium, activeFailed: entry.activeFailed, compact: true)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.kimiSmall"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemSmall])
    }
}

/// Small MiMo widget: the Token Plan quota with its used share and reset date.
struct MiMoSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MiMoSmallWidget", provider: ProviderWidgetTimelineProvider(provider: .mimo)) { entry in
            MediumLayoutView(state: entry.medium, activeFailed: entry.activeFailed, compact: true)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.mimo"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemSmall])
    }
}

/// Timeline of one provider's account from the shared snapshot (the app is the writer).
struct ProviderWidgetTimelineProvider: TimelineProvider {
    let provider: ProviderID

    private static let reloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> WidgetEntry {
        makeEntry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        let next = now.addingTimeInterval(Self.reloadInterval)
        completion(Timeline(entries: [makeEntry(now: now)], policy: .after(next)))
    }

    private func makeEntry(now: Date) -> WidgetEntry {
        let state = loadStoredWidgetState()
        let account = state.accounts.first { $0.provider == provider }
        let snapshot = account.flatMap { state.snapshots[$0.id] }
        let effective = account ?? AccountDescriptor(
            id: UUID(),
            provider: provider,
            region: provider == .kimi ? .intl : nil,
            label: provider == .kimi ? "Kimi" : "MiMo",
            credentialSlots: [],
            tier: nil,
            thresholds: [],
            budgets: [],
            displayCurrency: nil
        )
        return WidgetEntry(
            date: now,
            accountID: account?.id,
            scope: .account,
            layout: .ring,
            small: ViewStateBuilder.small(account: effective, snapshot: snapshot, now: now),
            medium: ViewStateBuilder.medium(
                accounts: account.map { [$0] } ?? [],
                snapshots: state.snapshots,
                focusAccountID: account?.id,
                now: now
            ),
            topModels: ViewStateBuilder.topModels(account: effective, snapshot: snapshot, scope: .account, now: now),
            dataUpdatedAt: snapshot?.updatedAt,
            activeFailed: false
        )
    }
}
