import SwiftUI
import TokenTankWidgetUI
import WidgetKit

/// Medium widget: list of account rows.
struct MediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MediumWidget", intent: TokenTankWidgetIntent.self, provider: WidgetTimelineProvider()) { entry in
            MediumLayoutView(state: entry.medium, activeFailed: entry.activeFailed)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.medium"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemMedium])
    }
}
