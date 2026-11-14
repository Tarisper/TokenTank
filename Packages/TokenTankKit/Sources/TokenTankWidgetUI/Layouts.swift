import SwiftUI

/// Layout of the small widget (§4): `ring` | `bars` | `rows`.
public enum SmallLayout {
    case ring
    case bars
    case rows
}

/// Small widget layout composition: one account, `ring`/`bars`/`rows` variants.
public struct SmallLayoutView: View {
    private let state: WidgetViewState.Small
    private let layout: SmallLayout
    private let activeFailed: Bool

    /// - Parameters:
    ///   - state: Resolved small layout parameters.
    ///   - layout: Layout variant.
    ///   - activeFailed: Show «could not update» over last-good data.
    public init(state: WidgetViewState.Small, layout: SmallLayout, activeFailed: Bool) {
        self.state = state
        self.layout = layout
        self.activeFailed = activeFailed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                StatusBadge(kind: state.status, text: state.statusText)
            }
            if let balanceText = state.balanceText {
                Text(balanceText)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            switch layout {
            case .ring:
                displayView
            case .bars:
                barsView
            case .rows:
                rowsView
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(2)
    }

    @ViewBuilder
    private var displayView: some View {
        switch state.display {
        case .ring(let fraction, let centerText, let captionText):
            Ring(centerText: centerText, captionText: captionText, fraction: fraction)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        case .noData(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var barsView: some View {
        VStack(spacing: 4) {
            ForEach(Array(state.bars.enumerated()), id: \.offset) { _, bar in
                Bar(
                    kind: bar.kind,
                    valueText: bar.valueText,
                    fraction: bar.fraction,
                    caption: bar.caption,
                    resetText: bar.resetText
                )
            }
            if state.bars.isEmpty {
                Text(noDataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rowsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let balanceText = state.balanceText {
                Text(balanceText)
                    .font(.caption)
                    .monospacedDigit()
            }
            StatusBadge(kind: state.status, text: state.statusText)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 4) {
            // A failed refresh replaces the mark: the footer is too narrow for both.
            if activeFailed {
                Text(LocalizedStringKey("widget.activeFailed"), bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(Color("StatusError", bundle: .module))
            } else if let updatedAtText = state.updatedAtText {
                UpdateIndicator(text: updatedAtText)
            }
        }
    }

    private var noDataText: String {
        if case .noData(let text) = state.display {
            return text
        }
        return ""
    }
}

/// Medium widget layout composition: quota bars of the selected account or the account list.
public struct MediumLayoutView: View {
    private let state: WidgetViewState.Medium
    private let activeFailed: Bool
    private let compact: Bool

    /// - Parameters:
    ///   - state: Resolved medium layout parameters.
    ///   - activeFailed: Show «could not update» over last-good data.
    ///   - compact: Bars put their reset hint under the track (small family).
    public init(state: WidgetViewState.Medium, activeFailed: Bool, compact: Bool = false) {
        self.state = state
        self.activeFailed = activeFailed
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let focus = state.focus {
                HStack {
                    Text(focus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    StatusBadge(kind: focus.status, text: focus.statusText)
                }
                ForEach(Array(focus.bars.enumerated()), id: \.offset) { _, bar in
                    Bar(
                        kind: bar.kind,
                        valueText: bar.valueText,
                        fraction: bar.fraction,
                        caption: bar.caption,
                        resetText: bar.resetText,
                        resetBelow: compact
                    )
                }
            } else if let emptyText = state.emptyText {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(state.rows.enumerated()), id: \.offset) { _, row in
                    AccountRowView(
                        label: row.label,
                        balanceText: row.balanceText,
                        detailText: row.detailText,
                        status: StatusBadge(kind: row.status, text: row.statusText)
                    )
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if activeFailed {
                    Text(LocalizedStringKey("widget.activeFailed"), bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(Color("StatusError", bundle: .module))
                } else if let updatedAtText = state.updatedAtText {
                    UpdateIndicator(text: updatedAtText)
                }
            }
        }
        .padding(2)
    }
}

/// Data-freshness mark: an icon and the update time, sized exactly like the
/// caption text it replaced.
private struct UpdateIndicator: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.clockwise")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

/// Top-models widget layout composition (rendering infrastructure, M3.9).
public struct TopModelsLayoutView: View {
    private let state: WidgetViewState.TopModels

    /// - Parameter state: Resolved top-models parameters.
    public init(state: WidgetViewState.TopModels) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(state.titleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                StatusBadge(kind: state.status, text: state.statusText)
            }
            if state.rows.isEmpty {
                Text(state.emptyText ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(state.rows.enumerated()), id: \.offset) { _, row in
                    TopModelRowView(name: row.name, valueText: row.valueText, fraction: row.fraction)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(2)
    }
}
