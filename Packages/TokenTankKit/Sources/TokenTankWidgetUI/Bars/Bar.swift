import SwiftUI

/// Kind of a progress bar; kinds are distinguished by their label, not by color (REQ-UI-12).
public enum BarKind {
    case quota
    case budget
    case threshold
    case forecast

    var labelKey: String {
        switch self {
        case .quota: "bar.quota"
        case .budget: "bar.budget"
        case .threshold: "bar.threshold"
        case .forecast: "bar.forecast"
        }
    }
}

/// Horizontal progress bar; the progress is always duplicated by the value text (REQ-UI-11).
public struct Bar: View {
    private let kind: BarKind
    private let valueText: String
    private let fraction: Double
    private let caption: String?
    private let resetText: String?
    private let resetBelow: Bool

    /// - Parameters:
    ///   - kind: Bar kind (drives the label when `caption` is absent).
    ///   - valueText: Preformatted value shown at the trailing edge.
    ///   - fraction: Consumed fraction (clamped to 0…1 for the track).
    ///   - caption: Per-limit caption overriding the generic kind label.
    ///   - resetText: Preformatted reset hint.
    ///   - resetBelow: Render the reset hint under the track instead of in the label row.
    public init(
        kind: BarKind,
        valueText: String,
        fraction: Double,
        caption: String? = nil,
        resetText: String? = nil,
        resetBelow: Bool = false
    ) {
        self.kind = kind
        self.valueText = valueText
        self.fraction = fraction
        self.caption = caption
        self.resetText = resetText
        self.resetBelow = resetBelow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Group {
                    if let caption {
                        Text(caption)
                    } else {
                        Text(LocalizedStringKey(kind.labelKey), bundle: .module)
                    }
                }
                .foregroundStyle(.secondary)
                if resetBelow == false, let resetText {
                    Text(resetText)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Text(valueText)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .font(.caption2)
            .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.15))
                    Capsule()
                        .fill(Color("BarFill", bundle: .module))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            .accessibilityLabel(caption.map { Text($0) } ?? Text(LocalizedStringKey(kind.labelKey), bundle: .module))
            .accessibilityValue(Text(valueText))
            if resetBelow, let resetText {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
