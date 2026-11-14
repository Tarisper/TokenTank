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
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(title: Text(state.label), status: state.status, statusText: state.statusText)
            if state.balanceTexts.isEmpty == false {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(state.balanceTexts.enumerated()), id: \.offset) { _, balance in
                        Text(balance)
                            .font(.system(size: state.balanceTexts.count > 1 ? 18 : layout == .rows ? 26 : 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .padding(.top, 5)
            }
            Spacer(minLength: 4)
            switch layout {
            case .ring:
                displayView
            case .bars:
                barsView
            case .rows:
                rowsView
            }
            Spacer(minLength: 2)
            WidgetFooter(statusText: state.status == .empty ? nil : state.statusText, updatedAtText: state.updatedAtText, activeFailed: activeFailed)
        }
    }

    @ViewBuilder
    private var displayView: some View {
        switch state.display {
        case .ring(let fraction, let centerText, let captionText):
            if state.balanceTexts.count > 1 {
                HStack(spacing: 8) {
                    Ring(centerText: centerText, captionText: "", fraction: fraction)
                        .frame(width: 40, height: 40)
                    Text(captionText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Ring(centerText: centerText, captionText: captionText, fraction: fraction)
                    .frame(height: state.statusText != nil ? 46 : state.balanceText == nil ? 76 : 58)
                    .frame(maxWidth: .infinity)
            }
        case .noData(let text):
            if state.balanceText == nil {
                WidgetEmptyState(symbol: "chart.bar", text: state.status == .empty ? state.statusText ?? text : text)
            } else {
                Text("widget.forecastUnavailable", bundle: .module)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var barsView: some View {
        VStack(spacing: 6) {
            ForEach(Array(state.bars.enumerated()), id: \.offset) { _, bar in
                Bar(
                    kind: bar.kind,
                    valueText: bar.valueText,
                    fraction: bar.fraction,
                    caption: bar.caption,
                    resetText: bar.resetText,
                    prominent: state.balanceText == nil && state.bars.count == 1
                )
            }
            if state.bars.isEmpty {
                displayView
            }
        }
    }

    @ViewBuilder
    private var rowsView: some View {
        switch state.display {
        case .ring(_, let centerText, let captionText):
            VStack(alignment: .leading, spacing: 2) {
                Text(centerText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(captionText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .noData:
            displayView
        }
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
    ///   - compact: Stack reset hints and emphasize a single quota in the small family.
    public init(state: WidgetViewState.Medium, activeFailed: Bool, compact: Bool = false) {
        self.state = state
        self.activeFailed = activeFailed
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let focus = state.focus {
                WidgetHeading(title: Text(focus.label), status: focus.status, statusText: focus.statusText)
                VStack(spacing: compact ? 4 : 12) {
                    ForEach(Array(focus.bars.enumerated()), id: \.offset) { _, bar in
                        Bar(
                            kind: bar.kind,
                            valueText: bar.valueText,
                            fraction: bar.fraction,
                            caption: bar.caption,
                            resetText: bar.resetText,
                            resetBelow: compact,
                            prominent: compact && focus.bars.count == 1
                        )
                    }
                }
                .padding(.top, compact ? 6 : 12)
                Spacer(minLength: 4)
                WidgetFooter(statusText: focus.statusText, updatedAtText: state.updatedAtText, activeFailed: activeFailed)
            } else if let emptyText = state.emptyText {
                WidgetHeading(title: Text("widget.name.medium", bundle: .module), status: nil, statusText: nil)
                WidgetEmptyState(symbol: "person.2", text: emptyText)
            } else {
                let visibleRows = Array(state.rows.prefix(activeFailed ? 2 : 3))
                HStack {
                    WidgetHeading(title: Text("widget.name.medium", bundle: .module), status: nil, statusText: nil)
                    if state.rows.count > visibleRows.count {
                        Text("widget.moreAccounts \(state.rows.count - visibleRows.count)", bundle: .module)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)
                VStack(spacing: 6) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                        AccountRowView(
                            label: row.label,
                            balanceText: row.balanceText,
                            detailText: row.statusText ?? row.detailText,
                            status: StatusBadge(kind: row.status, text: row.statusText, showsText: false)
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                if activeFailed {
                    WidgetFooter(statusText: nil, updatedAtText: nil, activeFailed: true)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Top-models widget layout composition.
public struct TopModelsLayoutView: View {
    private let state: WidgetViewState.TopModels

    /// - Parameter state: Resolved top-models parameters.
    public init(state: WidgetViewState.TopModels) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(title: Text(state.titleText), status: state.status, statusText: state.statusText)
            if state.rows.isEmpty {
                WidgetEmptyState(symbol: "chart.bar", text: state.emptyText ?? state.statusText ?? "")
            } else {
                VStack(alignment: .leading, spacing: state.statusText == nil ? 4 : 2) {
                    ForEach(Array(state.rows.enumerated()), id: \.offset) { _, row in
                        TopModelRowView(name: row.name, valueText: row.valueText, fraction: row.fraction, compact: state.statusText != nil)
                    }
                }
                .padding(.top, 5)
                Spacer(minLength: 0)
                if let statusText = state.statusText {
                    WidgetFooter(statusText: statusText, updatedAtText: nil, activeFailed: false)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Compact identity row shared by widget layouts.
private struct WidgetHeading: View {
    let title: Text
    let status: StatusKind?
    let statusText: String?

    var body: some View {
        HStack(spacing: 6) {
            title
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let status {
                StatusBadge(kind: status, text: statusText, showsText: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Status takes precedence over the quieter update timestamp.
private struct WidgetFooter: View {
    let statusText: String?
    let updatedAtText: String?
    let activeFailed: Bool

    var body: some View {
        Group {
            if activeFailed {
                Label {
                    Text("widget.activeFailed", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundStyle(Color("StatusError", bundle: .module))
                }
                .foregroundStyle(.primary)
            } else if let statusText {
                Text(statusText)
                    .foregroundStyle(.primary)
            } else if let updatedAtText {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                    Text(updatedAtText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 9))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Quiet placeholder that leaves room for the widget heading and status.
private struct WidgetEmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
