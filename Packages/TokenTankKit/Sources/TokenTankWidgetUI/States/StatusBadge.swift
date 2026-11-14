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

    /// - Parameters:
    ///   - kind: Status state.
    ///   - text: Preformatted text label (mandatory for `low`/`error`/`stale`).
    public init(kind: StatusKind, text: String?) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.color)
            if let text {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text ?? ""))
        // Without a text label the badge is decoration: never read the SF Symbol name.
        .accessibilityHidden(text == nil)
    }
}
