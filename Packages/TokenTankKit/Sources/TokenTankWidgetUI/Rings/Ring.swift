import SwiftUI

/// Circular gauge with a centered number and caption; «N days» and quota variants
/// differ by number format and caption, not by color (REQ-UI-12).
public struct Ring: View {
    private let centerText: String
    private let captionText: String
    private let fraction: Double?

    /// - Parameters:
    ///   - centerText: Preformatted number in the center.
    ///   - captionText: Preformatted caption under the number; empty omits it.
    ///   - fraction: Gauge fraction 0…1; `nil` renders the ring track empty.
    public init(centerText: String, captionText: String, fraction: Double?) {
        self.centerText = centerText
        self.captionText = captionText
        self.fraction = fraction
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.1), lineWidth: 5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(Color("AccentFill", bundle: .module), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if captionText.isEmpty == false {
                    Text(captionText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(captionText.isEmpty ? 3 : 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(captionText))
        .accessibilityValue(Text(centerText))
    }
}
