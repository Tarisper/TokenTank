import SwiftUI
import TokenTankWidgetUI
import WidgetKit

/// Top-models widget: rendering infrastructure (M3.9); data arrives with M6/M7.
struct TopModelsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TopModelsWidget", intent: TokenTankWidgetIntent.self, provider: WidgetTimelineProvider()) { entry in
            TopModelsLayoutView(state: entry.topModels)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName(Text(LocalizedStringKey("widget.name.topModels"), bundle: WidgetUIResources.bundle))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
