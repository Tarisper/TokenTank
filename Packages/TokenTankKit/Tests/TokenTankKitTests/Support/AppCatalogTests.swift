import Foundation
import Testing

/// The app target has no test target, so its string catalog is checked here.
/// `String(localized:)` builds the lookup key *with* format placeholders: an
/// entry named without them never resolves and the raw key leaks into the UI.
struct AppCatalogTests {
    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/TokenTank/Resources/Localizable.xcstrings")
    }

    @Test func notificationBodiesUsePlaceholderKeys() throws {
        let strings = try catalog()
        #expect(strings["notify.lowBalanceBody %@ %@ %@"] != nil)
        #expect(strings["notify.restoredBody %@"] != nil)
        #expect(strings["notify.lowBalanceBody"] == nil)
        #expect(strings["notify.restoredBody"] == nil)
    }

    @Test func notificationBodiesFormatEveryArgument() throws {
        let strings = try catalog()
        let low = try #require(value(of: "notify.lowBalanceBody %@ %@ %@", in: strings, locale: "en"))
        #expect(String(format: low, "Acc", "$5", "$10") == "Acc: $5 below threshold $10")
        let restored = try #require(value(of: "notify.restoredBody %@", in: strings, locale: "en"))
        #expect(String(format: restored, "Acc") == "Acc: recovered above the threshold")
        let lowRu = try #require(value(of: "notify.lowBalanceBody %@ %@ %@", in: strings, locale: "ru"))
        #expect(lowRu.contains("%1$@") && lowRu.contains("%3$@"))
    }

    private func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.catalogURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["strings"] as? [String: Any] ?? [:]
    }

    private func value(of key: String, in strings: [String: Any], locale: String) -> String? {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let localization = localizations[locale] as? [String: Any],
            let unit = localization["stringUnit"] as? [String: Any]
        else {
            return nil
        }
        return unit["value"] as? String
    }
}
