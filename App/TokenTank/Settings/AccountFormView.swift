import SwiftUI
import TokenTankKit
import TokenTankWidgetUI

/// Add/edit form of an account: settings, credential slots with key validation,
/// thresholds, budgets and base URL overrides (REQ-CFG-9).
struct AccountFormView: View {
    private static let tierTable: TierTable? = {
        guard
            let url = Bundle.main.url(forResource: "kimi-tiers", withExtension: "json")
                ?? Bundle.main.url(forResource: "kimi-tiers", withExtension: "json", subdirectory: "Config"),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(TierTable.self, from: data)
    }()

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    struct ThresholdRow: Identifiable {
        let id = UUID()
        var isQuota = false
        var currency = ""
        var quotaID = ""
        var unit: QuotaUnit = .credits
        var value = ""
        var rearm = "1.1"
    }

    struct BudgetRow: Identifiable {
        let id = UUID()
        var currency = ""
        var amount = ""
    }

    enum SlotCheck {
        case valid
        case failed(String)
    }

    private let existing: AccountDescriptor?
    private let accountID: UUID

    @State private var provider: ProviderID
    @State private var region: Region
    @State private var tierID: String
    @State private var label: String
    @State private var displayCurrencyAuto: Bool
    @State private var displayCurrency: String
    @State private var keyInputs: [String: String] = [:]
    @State private var overrideInputs: [String: String] = [:]
    @State private var slotChecks: [String: SlotCheck] = [:]
    @State private var checkingSlots: Set<String> = []
    @State private var expandedConnections: Set<String>
    @State private var thresholds: [ThresholdRow]
    @State private var budgets: [BudgetRow]
    @State private var gatewayConfirmed = false
    @State private var errorMessage: String?

    init(existing: AccountDescriptor?) {
        self.existing = existing
        let id = existing?.id ?? UUID()
        accountID = id
        _provider = State(initialValue: existing?.provider ?? .deepseek)
        _region = State(initialValue: existing?.region ?? .cn)
        _tierID = State(initialValue: existing?.tier ?? "")
        _label = State(initialValue: existing?.label ?? "")
        _displayCurrencyAuto = State(initialValue: existing?.displayCurrency == nil)
        _displayCurrency = State(initialValue: existing?.displayCurrency ?? "")
        _thresholds = State(initialValue: (existing?.thresholds ?? []).map {
            ThresholdRow(
                isQuota: $0.unit != nil,
                currency: $0.currency ?? "",
                quotaID: $0.quotaID ?? "",
                unit: $0.unit ?? .credits,
                value: "\($0.value)",
                rearm: "\($0.rearmFraction)"
            )
        })
        _budgets = State(initialValue: (existing?.budgets ?? []).map {
            BudgetRow(currency: $0.currency, amount: "\($0.amount)")
        })
        var overrides: [String: String] = [:]
        for slot in existing?.credentialSlots ?? [] {
            overrides[slot.id] = slot.baseURLOverride?.absoluteString ?? ""
        }
        _overrideInputs = State(initialValue: overrides)
        _expandedConnections = State(initialValue: Set(overrides.filter { $0.value.isEmpty == false }.keys))
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(
                title: existing == nil ? "form.title.add" : "form.title.edit",
                subtitle: "form.subtitle",
                symbol: existing == nil ? "person.crop.circle.badge.plus" : "person.crop.circle"
            )
            .padding(24)
            Divider()
            Form {
                Section {
                    Picker("form.provider", selection: $provider) {
                        ForEach([ProviderID.deepseek, .kimi, .mimo], id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .disabled(existing != nil)
                    if provider == .kimi {
                        Picker("form.region", selection: $region) {
                            Text("form.region.cn").tag(Region.cn)
                            Text("form.region.intl").tag(Region.intl)
                        }
                        Picker("form.tier", selection: $tierID) {
                            Text("form.tier.none").tag("")
                            ForEach(Self.tierTable?.tiers ?? [], id: \.id) { tier in
                                Text(tier.id).tag(tier.id)
                            }
                        }
                    }
                    TextField("form.label", text: $label)
                    Toggle("form.displayCurrency", isOn: $displayCurrencyAuto)
                        .toggleStyle(.switch)
                    if displayCurrencyAuto == false {
                        TextField("form.currencyCode", text: $displayCurrency)
                    }
                } header: {
                    Label("form.section.main", systemImage: "person.crop.rectangle")
                }

                ForEach(slotPlan, id: \.id) { slot in
                    slotEditor(slot)
                }
                if hasCustomGateway {
                    Section {
                        Toggle("form.gatewayConfirm", isOn: $gatewayConfirmed)
                            .toggleStyle(.switch)
                    }
                }

                Section {
                    ForEach($thresholds) { row in
                        thresholdEditor(row)
                    }
                    Button {
                        thresholds.append(ThresholdRow())
                    } label: {
                        Label("form.threshold.add", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Label("form.section.thresholds", systemImage: "bell.badge")
                } footer: {
                    Text("form.threshold.description")
                }

                Section {
                    ForEach($budgets) { row in
                        budgetEditor(row)
                    }
                    Button {
                        budgets.append(BudgetRow())
                    } label: {
                        Label("form.budget.add", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Label("form.section.budgets", systemImage: "chart.bar")
                }
            }
            .formStyle(.grouped)
            .textFieldStyle(.roundedBorder)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 640, height: 700)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Label("form.credentialsNote", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Button("form.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("form.save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var hasCustomGateway: Bool {
        for slot in slotPlan {
            let raw = (overrideInputs[slot.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: raw), raw.isEmpty == false else { continue }
            if BaseURLPolicy.validate(url, provider: provider, region: provider == .kimi ? region : nil) == .customGateway {
                return true
            }
        }
        return false
    }

    private var slotPlan: [(id: String, kind: KeyKind, title: String)] {
        switch provider {
        case .deepseek:
            return [("sk", .apiKey, String(localized: "form.key.sk"))]
        case .kimi:
            return [
                ("sk", .apiKey, String(localized: "form.key.sk")),
                ("coding", .coding, String(localized: "form.key.coding")),
                ("admin", .admin, String(localized: "form.key.admin")),
            ]
        case .mimo:
            return [
                ("sk", .apiKey, String(localized: "form.key.sk")),
                ("tp", .tokenPlan, String(localized: "form.key.tp")),
            ]
        }
    }

    @ViewBuilder
    private func slotEditor(_ slot: (id: String, kind: KeyKind, title: String)) -> some View {
        let ref = keychainRef(slot.id)
        let stored = model.keychain.key(for: ref)
        Section {
            LabeledContent("form.key.new") {
                SecureField("", text: keyBinding(slot.id), prompt: Text(stored != nil ? "••••••••" : ""))
                    .frame(maxWidth: 320)
            }
            if let stored, keyInputs[slot.id]?.isEmpty != false {
                Text("form.key.current \(KeyMask.format(stored))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    Task {
                        checkingSlots.insert(slot.id)
                        defer { checkingSlots.remove(slot.id) }
                        await checkSlot(slot, ref: ref)
                    }
                } label: {
                    Label("form.key.check", systemImage: "checkmark.shield")
                }
                .disabled(checkingSlots.contains(slot.id))
                if checkingSlots.contains(slot.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    switch slotChecks[slot.id] {
                    case .valid:
                        Label("form.key.valid", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            DisclosureGroup("form.connection.advanced", isExpanded: Binding(
                get: { expandedConnections.contains(slot.id) },
                set: { expanded in
                    if expanded {
                        expandedConnections.insert(slot.id)
                    } else {
                        expandedConnections.remove(slot.id)
                    }
                }
            )) {
                LabeledContent("form.override") {
                    TextField("", text: overrideBinding(slot.id), prompt: Text("form.override.placeholder"))
                        .frame(maxWidth: 320)
                }
            }
        } header: {
            Label(slot.title, systemImage: "key.horizontal")
        }
    }

    private func thresholdEditor(_ row: Binding<ThresholdRow>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("form.threshold.target", selection: row.isQuota) {
                    Text("form.threshold.money").tag(false)
                    Text("form.threshold.quota").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220, alignment: .leading)
                Spacer()
                Button(role: .destructive) {
                    thresholds.removeAll { $0.id == row.wrappedValue.id }
                } label: {
                    Label("form.threshold.remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("form.threshold.remove")
            }
            if row.wrappedValue.isQuota {
                TextField("form.threshold.quotaID", text: row.quotaID)
                Picker("form.threshold.unit", selection: row.unit) {
                    ForEach(QuotaUnit.allCases, id: \.self) { unit in
                        Text(unitTitle(unit)).tag(unit)
                    }
                }
            } else {
                TextField("form.threshold.currency", text: row.currency)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("form.threshold.value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("form.threshold.value", text: row.value)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("form.threshold.rearm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("form.threshold.rearm", text: row.rearm)
                        .labelsHidden()
                }
                .frame(width: 150)
            }
        }
        .padding(.vertical, 6)
    }

    private func budgetEditor(_ row: Binding<BudgetRow>) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("form.budget.currency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("form.budget.currency", text: row.currency)
                    .labelsHidden()
            }
            .frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text("form.budget.amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("form.budget.amount", text: row.amount)
                    .labelsHidden()
            }
            Button(role: .destructive) {
                budgets.removeAll { $0.id == row.wrappedValue.id }
            } label: {
                Label("form.budget.remove", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("form.budget.remove")
            .padding(.bottom, 4)
        }
        .padding(.vertical, 6)
    }

    private func keyBinding(_ slotID: String) -> Binding<String> {
        Binding(
            get: { keyInputs[slotID] ?? "" },
            set: { keyInputs[slotID] = $0; slotChecks[slotID] = nil }
        )
    }

    private func overrideBinding(_ slotID: String) -> Binding<String> {
        Binding(
            get: { overrideInputs[slotID] ?? "" },
            set: { overrideInputs[slotID] = $0; gatewayConfirmed = false }
        )
    }

    private func keychainRef(_ slotID: String) -> String {
        "\(accountID.uuidString)/\(slotID)"
    }

    private func checkSlot(_ slot: (id: String, kind: KeyKind, title: String), ref: String) async {
        let key = keyInputs[slot.id].flatMap { $0.isEmpty ? nil : $0 } ?? model.keychain.key(for: ref) ?? ""
        let rawOverride = (overrideInputs[slot.id] ?? "").trimmingCharacters(in: .whitespaces)
        var baseURL: URL?
        if rawOverride.isEmpty == false {
            guard
                let url = URL(string: rawOverride),
                BaseURLPolicy.validate(url, provider: provider, region: provider == .kimi ? region : nil) != .invalid
            else {
                slotChecks[slot.id] = .failed(String(localized: "form.override.invalid"))
                return
            }
            guard BaseURLPolicy.validate(url, provider: provider, region: provider == .kimi ? region : nil) != .customGateway || gatewayConfirmed else {
                slotChecks[slot.id] = .failed(String(localized: "form.error.gateway"))
                return
            }
            baseURL = url
        }
        let credential = CredentialSlot(id: slot.id, kind: slot.kind, keychainRef: ref, baseURLOverride: baseURL)
        switch await model.validateKey(key, slot: credential, account: draftDescriptor(slots: []), customGatewayConfirmed: gatewayConfirmed) {
        case .success:
            slotChecks[slot.id] = .valid
        case .failure(let error):
            slotChecks[slot.id] = .failed(ProviderErrorText.text(for: error))
        }
    }

    private func save() {
        var slots: [CredentialSlot] = []
        for slot in slotPlan {
            let ref = keychainRef(slot.id)
            // Empty new slots are not persisted: without a key they would only
            // produce an `invalidKey` section on every fetch.
            let isExisting = existing?.credentialSlots.contains { $0.id == slot.id } ?? false
            guard isExisting || keyInputs[slot.id]?.isEmpty == false else { continue }
            var override: URL?
            let rawOverride = (overrideInputs[slot.id] ?? "").trimmingCharacters(in: .whitespaces)
            if rawOverride.isEmpty == false {
                guard let url = URL(string: rawOverride) else {
                    errorMessage = String(localized: "form.override.invalid")
                    return
                }
                switch BaseURLPolicy.validate(url, provider: provider, region: provider == .kimi ? region : nil) {
                case .invalid:
                    errorMessage = String(localized: "form.override.invalid")
                    return
                case .customGateway:
                    guard gatewayConfirmed else {
                        errorMessage = String(localized: "form.error.gateway")
                        return
                    }
                    override = url
                case .allowed:
                    override = url
                }
            }
            slots.append(CredentialSlot(id: slot.id, kind: slot.kind, keychainRef: ref, baseURLOverride: override))
        }

        var parsedThresholds: [Threshold] = []
        for row in thresholds {
            guard let value = decimal(row.value), let rearm = decimal(row.rearm) else {
                errorMessage = String(localized: "form.error.thresholds")
                return
            }
            do {
                parsedThresholds.append(try Threshold(
                    currency: row.isQuota ? nil : row.currency.trimmingCharacters(in: .whitespaces).uppercased(),
                    unit: row.isQuota ? row.unit : nil,
                    quotaID: row.isQuota ? row.quotaID.trimmingCharacters(in: .whitespaces) : nil,
                    value: value,
                    rearmFraction: rearm
                ))
            } catch let error as ThresholdError {
                errorMessage = thresholdMessage(error)
                return
            } catch {
                errorMessage = String(localized: "form.error.thresholds")
                return
            }
        }

        var parsedBudgets: [AccountBudget] = []
        for row in budgets {
            guard let amount = decimal(row.amount) else {
                errorMessage = String(localized: "form.error.budgets")
                return
            }
            parsedBudgets.append(AccountBudget(currency: row.currency, amount: amount))
        }

        for slot in slots {
            if let value = keyInputs[slot.id], value.isEmpty == false {
                do {
                    try model.keychain.set(value, for: slot.keychainRef)
                } catch {
                    errorMessage = String(localized: "form.error.keychain")
                    return
                }
            }
        }

        let account = draftDescriptor(
            slots: slots,
            thresholds: parsedThresholds,
            budgets: parsedBudgets
        )
        do {
            try model.save(account)
            dismiss()
        } catch {
            errorMessage = String(localized: "form.error.save")
        }
    }

    private func draftDescriptor(
        slots: [CredentialSlot],
        thresholds: [Threshold] = [],
        budgets: [AccountBudget] = []
    ) -> AccountDescriptor {
        AccountDescriptor(
            id: accountID,
            provider: provider,
            region: provider == .kimi ? region : nil,
            label: label,
            credentialSlots: slots,
            tier: tierID.isEmpty ? nil : tierID,
            thresholds: thresholds,
            budgets: budgets,
            displayCurrency: displayCurrencyAuto ? nil : displayCurrency
        )
    }

    /// Parses a user-entered decimal regardless of the input locale: `1,5`,
    /// `1 000` and `1.5` all mean the same numbers they look like.
    private func decimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let valid = normalized.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
        return valid ? Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) : nil
    }

    private func unitTitle(_ unit: QuotaUnit) -> String {
        let title = switch unit {
        case .credits: String(localized: "form.unit.credits")
        case .tokens: String(localized: "form.unit.tokens")
        case .requests: String(localized: "form.unit.requests")
        case .percent: String(localized: "form.unit.percent")
        }
        return title
    }

    private func thresholdMessage(_ error: ThresholdError) -> String {
        let message = switch error {
        case .unknownCurrency: String(localized: "form.error.threshold.currency")
        case .emptyQuotaID: String(localized: "form.error.threshold.quotaID")
        case .nonPositiveValue: String(localized: "form.error.threshold.value")
        case .invalidRearm: String(localized: "form.error.threshold.rearm")
        case .conflictingTarget, .quotaIDMismatch: String(localized: "form.error.thresholds")
        }
        return message
    }
}
