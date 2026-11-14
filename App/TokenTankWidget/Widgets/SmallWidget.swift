import SwiftUI
import TokenTankWidgetUI
import WidgetKit

/// Small widget: one account; `ring`/`bars`/`rows` layouts (§4).
struct SmallWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SmallWidget", intent: TokenTankWidgetIntent.self, provider: WidgetTimelineProvider()) { entry in
            SmallLayoutView(state: entry.small, layout: entry.layout.uiLayout, activeFailed: entry.activeFailed)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.small"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemSmall])
    }
}

extension SmallLayoutOption {
    var uiLayout: SmallLayout {
        switch self {
        case .ring: .ring
        case .bars: .bars
        case .rows: .rows
        }
    }
}
