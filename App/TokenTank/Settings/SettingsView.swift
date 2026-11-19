import SwiftUI
import TokenTankKit

/// Settings window: account list with add/edit/delete, deep-link aware.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: AccountDescriptor?
    @State private var creating = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var refreshMinutes = RefreshSettings.minutes

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                SettingsHeader(title: "settings.title", subtitle: "settings.subtitle", symbol: "fuelpump")
                Button {
                    creating = true
                } label: {
                    Label("settings.add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            Divider()
            Form {
                Section {
                    if model.accounts.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle.badge.plus")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("settings.empty.title")
                                .font(.headline)
                            Text("settings.empty.description")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    ForEach(model.accounts) { account in
                        HStack(spacing: 12) {
                            Button {
                                editing = account
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(account.provider.displayName.prefix(1)))
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 36)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.label)
                                            .fontWeight(.medium)
                                        Text(account.provider.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("settings.edit", systemImage: "pencil") {
                                    editing = account
                                }
                                Button("settings.delete", systemImage: "trash", role: .destructive) {
                                    model.delete(account)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 20, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel(Text("settings.accountActions"))
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label("settings.accounts", systemImage: "person.2")
                }
                Section {
                    Picker("settings.refreshInterval", selection: $refreshMinutes) {
                        ForEach(RefreshSettings.options, id: \.self) { minutes in
                            Text("settings.refresh.minutes \(minutes)").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: refreshMinutes) { _, minutes in
                        model.setRefreshInterval(minutes: minutes)
                    }
                    Toggle("settings.launchAtLogin", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            if LaunchAtLogin.setEnabled(enabled) == false {
                                launchAtLogin = LaunchAtLogin.isEnabled
                            }
                        }
                } header: {
                    Label("settings.general", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("settings.refresh.description")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 640, height: 580)
        .sheet(item: $editing) { account in
            AccountFormView(existing: account)
                .environmentObject(model)
        }
        .sheet(isPresented: $creating) {
            AccountFormView(existing: nil)
                .environmentObject(model)
        }
        .onChange(of: model.route) { _, route in
            switch route {
            case .add:
                creating = true
            case .account(let id):
                editing = model.accounts.first { $0.id == id }
            case nil:
                break
            }
        }
    }
}
