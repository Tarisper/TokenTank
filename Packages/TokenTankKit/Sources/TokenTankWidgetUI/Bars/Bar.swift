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
    private let prominent: Bool

    /// - Parameters:
    ///   - kind: Bar kind (drives the label when `caption` is absent).
    ///   - valueText: Preformatted value shown at the trailing edge.
    ///   - fraction: Consumed fraction (clamped to 0…1 for the track).
    ///   - caption: Per-limit caption overriding the generic kind label.
    ///   - resetText: Preformatted reset hint.
    ///   - resetBelow: Render the reset hint under the track instead of in the label row.
    ///   - prominent: Emphasize the value when this is the widget's only quota.
    public init(
        kind: BarKind,
        valueText: String,
        fraction: Double,
        caption: String? = nil,
        resetText: String? = nil,
        resetBelow: Bool = false,
        prominent: Bool = false
    ) {
        self.kind = kind
        self.valueText = valueText
        self.fraction = fraction
        self.caption = caption
        self.resetText = resetText
        self.resetBelow = resetBelow
        self.prominent = prominent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 5 : 3) {
            if prominent {
                HStack(spacing: 4) {
                    captionView
                        .font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 0)
                    Text("widget.used", bundle: .module)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Text(valueText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                HStack(spacing: 5) {
                    captionView
                        .font(.system(size: 10, weight: .medium))
                    if resetBelow == false, let resetText {
                        Text(resetText)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(valueText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                    Capsule()
                        .fill(Color("BarFill", bundle: .module))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: prominent ? 5 : 4)
            if resetBelow || prominent, let resetText {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { Text($0) } ?? Text(LocalizedStringKey(kind.labelKey), bundle: .module))
        .accessibilityValue(Text([valueText, resetText].compactMap { $0 }.joined(separator: ", ")))
    }

    private var captionView: some View {
        Group {
            if let caption {
                Text(caption)
            } else {
                Text(LocalizedStringKey(kind.labelKey), bundle: .module)
            }
        }
        .foregroundStyle(.secondary)
    }
}
