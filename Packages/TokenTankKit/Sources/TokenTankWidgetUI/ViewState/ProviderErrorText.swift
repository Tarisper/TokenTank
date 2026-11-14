import Foundation
import TokenTankKit

/// Localized status text of a provider failure (REQ-UI-10). The taxonomy is
/// closed, so every case maps to a catalog key instead of a Swift description.
public enum ProviderErrorText {
    /// - Parameters:
    ///   - error: Provider failure.
    ///   - locale: Formatting locale.
    /// - Returns: Short localized text for the widget or the account form.
    public static func text(for error: ProviderError, locale: Locale = .current) -> String {
        let text = switch error {
        case .invalidKey:
            String(localized: "error.invalidKey", bundle: .module, locale: locale)
        case .regionMismatch:
            String(localized: "error.regionMismatch", bundle: .module, locale: locale)
        case .rateLimited:
            String(localized: "error.rateLimited", bundle: .module, locale: locale)
        case .server(let status):
            String(localized: "error.server \(status)", bundle: .module, locale: locale)
        case .network:
            String(localized: "error.network", bundle: .module, locale: locale)
        case .decoding:
            String(localized: "error.decoding", bundle: .module, locale: locale)
        case .dataNotReady:
            String(localized: "error.dataNotReady", bundle: .module, locale: locale)
        case .unsupported:
            String(localized: "error.unsupported", bundle: .module, locale: locale)
        }
        return text
    }
}
