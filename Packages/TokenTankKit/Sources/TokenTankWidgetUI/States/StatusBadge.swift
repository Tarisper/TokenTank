import SwiftUI

/// Status state of an account or a section (§4).
public enum StatusKind {
    case ok
    case low
    case stale
    case error
    case updating
    case empty
    case noData
    case zeroSpend
    case unsupported

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .low: "exclamationmark.triangle.fill"
        case .stale: "clock.fill"
        case .error: "xmark.octagon.fill"
        case .updating: "arrow.triangle.2.circlepath"
        case .empty: "plus.circle"
        case .noData: "questionmark.circle"
        case .zeroSpend: "circle.dotted"
        case .unsupported: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: Color("StatusOK", bundle: .module)
        case .low: Color("StatusLow", bundle: .module)
        case .error: Color("StatusError", bundle: .module)
        case .updating: Color("StatusUpdating", bundle: .module)
        case .stale, .empty, .noData, .zeroSpend, .unsupported: Color("StatusUnsupported", bundle: .module)
        }
    }
}

/// Status badge: color + unique SF Symbol (REQ-UI-10); the text label is required
/// for `low`, `error` and `stale` and is passed in preformatted.
public struct StatusBadge: View {
    private let kind: StatusKind
    private let text: String?
    private let showsText: Bool

    /// - Parameters:
    ///   - kind: Status state.
    ///   - text: Preformatted text label (mandatory for `low`/`error`/`stale`).
    ///   - showsText: Whether to show the label beside the symbol; accessibility keeps the full text.
    public init(kind: StatusKind, text: String?, showsText: Bool = true) {
        self.kind = kind
        self.text = text
        self.showsText = showsText
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind.color)
            if showsText, let text {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text ?? ""))
        // Without a text label the badge is decoration: never read the SF Symbol name.
        .accessibilityHidden(text == nil)
    }
}
