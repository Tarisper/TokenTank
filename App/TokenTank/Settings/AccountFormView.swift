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
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                Section("form.section.main") {
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
                    if displayCurrencyAuto == false {
                        TextField("form.currencyCode", text: $displayCurrency)
                    }
                }

                ForEach(slotPlan, id: \.id) { slot in
                    slotEditor(slot)
                }
                if hasCustomGateway {
                    Section {
                        Toggle("form.gatewayConfirm", isOn: $gatewayConfirmed)
                    }
                }

                Section("form.section.thresholds") {
                    ForEach($thresholds) { $row in
                        thresholdEditor($row)
                    }
                    Button("form.threshold.add") {
                        thresholds.append(ThresholdRow())
                    }
                }

                Section("form.section.budgets") {
                    ForEach($budgets) { $row in
                        HStack {
                            TextField("form.budget.currency", text: $row.currency)
                                .frame(width: 90)
                            TextField("form.budget.amount", text: $row.amount)
                        }
                    }
                    Button("form.budget.add") {
                        budgets.append(BudgetRow())
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                }
                .formStyle(.grouped)
                .padding(20)
            }
            Divider()
            HStack {
                Button("form.cancel") { dismiss() }
                Spacer()
                Button("form.save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
        .frame(width: 560, height: 620)
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
            if let stored, keyInputs[slot.id]?.isEmpty != false {
                Text("form.key.current \(KeyMask.format(stored))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("form.key.new") {
                SecureField("", text: keyBinding(slot.id), prompt: Text(stored != nil ? "••••••••" : ""))
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("form.override") {
                TextField("", text: overrideBinding(slot.id))
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("form.key.check") {
                    Task { await checkSlot(slot, ref: ref) }
                }
                switch slotChecks[slot.id] {
                case .valid:
                    Text("form.key.valid").foregroundStyle(.green)
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                case nil:
                    EmptyView()
                }
            }
        } header: {
            Text(slot.title)
        }
    }

    @ViewBuilder
    private func thresholdEditor(_ row: Binding<ThresholdRow>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("form.threshold.target", selection: row.isQuota) {
                Text("form.threshold.money").tag(false)
                Text("form.threshold.quota").tag(true)
            }
            .pickerStyle(.segmented)
            if row.wrappedValue.isQuota {
                HStack {
                    TextField("form.threshold.quotaID", text: row.quotaID)
                    Picker("form.threshold.unit", selection: row.unit) {
                        ForEach(QuotaUnit.allCases, id: \.self) { unit in
                            Text(unitTitle(unit)).tag(unit)
                        }
                    }
                }
            } else {
                TextField("form.threshold.currency", text: row.currency)
                    .frame(width: 90)
            }
            HStack {
                TextField("form.threshold.value", text: row.value)
                TextField("form.threshold.rearm", text: row.rearm)
                    .frame(width: 80)
                Spacer()
                Button(role: .destructive) {
                    thresholds.removeAll { $0.id == row.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
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
            baseURL = url
        }
        let credential = CredentialSlot(id: slot.id, kind: slot.kind, keychainRef: ref, baseURLOverride: baseURL)
        switch await model.validateKey(key, slot: credential, account: draftDescriptor(slots: [])) {
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
