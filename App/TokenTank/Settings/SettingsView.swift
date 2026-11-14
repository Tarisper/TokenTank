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
            List {
                ForEach(model.accounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.label)
                            Text(account.provider.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("settings.edit") {
                            editing = account
                        }
                        Button("settings.delete", role: .destructive) {
                            model.delete(account)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Picker("settings.refreshInterval", selection: $refreshMinutes) {
                    ForEach(RefreshSettings.options, id: \.self) { minutes in
                        Text("settings.refresh.minutes \(minutes)").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: refreshMinutes) { _, minutes in
                    model.setRefreshInterval(minutes: minutes)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            HStack {
                Button("settings.add") {
                    creating = true
                }
                Spacer()
                Toggle("settings.launchAtLogin", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if LaunchAtLogin.setEnabled(enabled) == false {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }
            .padding(8)
        }
        .frame(width: 520, height: 440)
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
