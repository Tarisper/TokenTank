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
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(balanceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer()
            status
        }
    }
}

/// One model row of the top-models widget; the bar is optional (REQ-TOP-4).
public struct TopModelRowView: View {
    private let name: String
    private let valueText: String
    private let fraction: Double?

    /// - Parameters:
    ///   - name: Model name.
    ///   - valueText: Preformatted spend/usage value.
    ///   - fraction: Share of the scope total; `nil` renders without a bar.
    public init(name: String, valueText: String, fraction: Double?) {
        self.name = name
        self.valueText = valueText
        self.fraction = fraction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.15))
                        Capsule()
                            .fill(Color("BarFill", bundle: .module))
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(valueText))
    }
}
