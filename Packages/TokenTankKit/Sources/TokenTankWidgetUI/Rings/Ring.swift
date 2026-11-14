import SwiftUI

/// Circular gauge with a centered number and caption; «N days» and quota variants
/// differ by number format and caption, not by color (REQ-UI-12).
public struct Ring: View {
    private let centerText: String
    private let captionText: String
    private let fraction: Double?

    /// - Parameters:
    ///   - centerText: Preformatted number in the center.
    ///   - captionText: Preformatted caption under the number.
    ///   - fraction: Gauge fraction 0…1; `nil` renders the ring track empty.
    public init(centerText: String, captionText: String, fraction: Double?) {
        self.centerText = centerText
        self.captionText = captionText
        self.fraction = fraction
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.15), lineWidth: 6)
            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(Color("AccentFill", bundle: .module), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(centerText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(captionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(captionText))
        .accessibilityValue(Text(centerText))
    }
}
