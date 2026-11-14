import Foundation
import TokenTankKit

/// Localized display name of a provider for the settings UI.
extension ProviderID {
    var displayName: String {
        let name = switch self {
        case .deepseek: String(localized: "provider.deepseek")
        case .kimi: String(localized: "provider.kimi")
        case .mimo: String(localized: "provider.mimo")
        }
        return name
    }
}
