import Foundation

/// Routes of `tokentank://` deep links (REQ-UI-12).
public enum AppRoute: Equatable {
    case add
    case account(UUID)
}

/// Parses `tokentank://` URLs for the app and widgets.
public enum URLRouter {
    /// Resolves the route of a deep link.
    /// - Parameter url: Incoming URL.
    /// - Returns: Route, or `nil` for unknown links.
    public static func route(for url: URL) -> AppRoute? {
        guard url.scheme == "tokentank" else { return nil }
        switch url.host {
        case "add":
            return .add
        case "account":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return .account(id)
        default:
            return nil
        }
    }
}
