import AppIntents
import Foundation
import TokenTankKit
import TokenTankWidgetUI

/// Account picker entity backed by the shared `AccountStore`.
struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.intent.accountType", bundle: WidgetUIResources.bundle)
    )
    static var defaultQuery = AccountQuery()

    var id: UUID
    var displayRepresentation: DisplayRepresentation

    init(id: UUID, label: String) {
        self.id = id
        self.displayRepresentation = DisplayRepresentation(title: "\(label)")
    }
}

struct AccountQuery: EntityQuery {
    private func entities() -> [AccountEntity] {
        let defaults = AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        return AccountStore(defaults: defaults).accounts().map {
            AccountEntity(id: $0.id, label: $0.label)
        }
    }

    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        entities()
    }
}

/// Scope of quota-oriented layouts.
enum ScopeOption: String, AppEnum {
    case account
    case quota

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.intent.scopeType", bundle: WidgetUIResources.bundle)
    )
    static var caseDisplayRepresentations: [ScopeOption: DisplayRepresentation] = [
        .account: DisplayRepresentation(title: LocalizedStringResource("widget.scope.account", bundle: WidgetUIResources.bundle)),
        .quota: DisplayRepresentation(title: LocalizedStringResource("widget.scope.quota", bundle: WidgetUIResources.bundle)),
    ]
}

/// Layout of the small widget (§4).
enum SmallLayoutOption: String, AppEnum {
    case ring
    case bars
    case rows

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.intent.layoutType", bundle: WidgetUIResources.bundle)
    )
    static var caseDisplayRepresentations: [SmallLayoutOption: DisplayRepresentation] = [
        .ring: DisplayRepresentation(title: LocalizedStringResource("widget.layout.ring", bundle: WidgetUIResources.bundle)),
        .bars: DisplayRepresentation(title: LocalizedStringResource("widget.layout.bars", bundle: WidgetUIResources.bundle)),
        .rows: DisplayRepresentation(title: LocalizedStringResource("widget.layout.rows", bundle: WidgetUIResources.bundle)),
    ]
}

/// Widget configuration intent.
struct TokenTankWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "widget.intent.title",
        bundle: WidgetUIResources.bundle
    )
    static var description = IntentDescription(
        LocalizedStringResource("widget.intent.description", bundle: WidgetUIResources.bundle)
    )

    @Parameter(title: LocalizedStringResource("widget.intent.account", bundle: WidgetUIResources.bundle))
    var account: AccountEntity?

    @Parameter(title: LocalizedStringResource("widget.intent.scope", bundle: WidgetUIResources.bundle))
    var scope: ScopeOption?

    @Parameter(title: LocalizedStringResource("widget.intent.layout", bundle: WidgetUIResources.bundle))
    var layout: SmallLayoutOption?

    @Parameter(
        title: LocalizedStringResource("widget.intent.active", bundle: WidgetUIResources.bundle),
        default: false
    )
    var active: Bool?
}

extension ScopeOption {
    /// Resolves to a `Scope`, using the first known quota id for `.quota`.
    func resolved(quotaID: String?) -> Scope {
        switch self {
        case .account:
            return .account
        case .quota:
            return .quota(quotaID ?? MiMoAdapter.quotaID)
        }
    }
}
