import SwiftUI

/// One account row of the medium widget.
public struct AccountRowView: View {
    private let label: String
    private let balanceText: String
    private let detailText: String?
    private let status: StatusBadge

    /// - Parameters:
    ///   - label: Account label.
    ///   - balanceText: Preformatted balances, one per currency (display currency first).
    ///   - detailText: Preformatted secondary line (e.g. «≈ 22 days left»).
    ///   - status: Status badge.
    public init(label: String, balanceText: String, detailText: String?, status: StatusBadge) {
        self.label = label
        self.balanceText = balanceText
        self.detailText = detailText
        self.status = status
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            status
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text(balanceText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                }
                if let detailText {
                    Text(detailText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }
}

/// One model row of the top-models widget; the bar is optional (REQ-TOP-4).
public struct TopModelRowView: View {
    private let name: String
    private let valueText: String
    private let fraction: Double?
    private let compact: Bool

    /// - Parameters:
    ///   - name: Model name.
    ///   - valueText: Preformatted spend/usage value.
    ///   - fraction: Share of the scope total; `nil` renders without a bar.
    ///   - compact: Use denser labels when the layout needs room for a status message.
    public init(name: String, valueText: String, fraction: Double?, compact: Bool = false) {
        self.name = name
        self.valueText = valueText
        self.fraction = fraction
        self.compact = compact
    }

    public var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(valueText)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            } else {
                adaptiveRow
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(valueText))
    }

    private var adaptiveRow: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Text(valueText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
                if fraction != nil {
                    track
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    if fraction != nil {
                        track
                    }
                    Text(valueText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.1))
                Capsule()
                    .fill(Color("BarFill", bundle: .module))
                    .frame(width: proxy.size.width * min(max(fraction ?? 0, 0), 1))
            }
        }
        .frame(height: 3)
    }
}
