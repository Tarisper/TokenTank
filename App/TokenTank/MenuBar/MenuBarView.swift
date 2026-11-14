import SwiftUI
import TokenTankKit
import TokenTankWidgetUI

/// Menu bar content: account rows, manual refresh and app actions.
struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.accounts.isEmpty {
            Text("menu.noAccounts")
            Button("menu.addAccount") {
                model.route = .add
                SettingsWindow.show(openSettings)
            }
        } else {
            ForEach(model.accounts) { account in
                Button {
                    model.route = .account(account.id)
                    SettingsWindow.show(openSettings)
                } label: {
                    Text(rowTitle(account))
                }
            }
            Divider()
            Button("menu.refreshAll") {
                Task { await model.refreshAll() }
            }
            .disabled(model.refreshing.isEmpty == false)
        }
        Button {
            SettingsWindow.show(openSettings)
        } label: {
            Label("menu.settings", systemImage: "gearshape")
        }
        Divider()
        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func rowTitle(_ account: AccountDescriptor) -> String {
        var parts = [account.label]
        let balance = balanceSummary(account)
        let limits = ViewStateBuilder.limitsText(of: account, snapshot: model.snapshots[account.id])
        if let balance {
            parts.append(balance)
        }
        if let limits, limits != balance {
            parts.append(limits)
        }
        if model.refreshing.contains(account.id) {
            parts.append(String(localized: "menu.refreshing"))
        } else if model.failedRefreshes.contains(account.id) {
            parts.append(String(localized: "menu.failed"))
        } else if account.credentialSlots.contains(where: { slot in
            guard let url = slot.baseURLOverride else { return false }
            return BaseURLPolicy.validate(url, provider: account.provider, region: account.region) == .customGateway
        }) {
            parts.append(String(localized: "menu.gateway"))
        }
        return parts.joined(separator: " · ")
    }

    private func balanceSummary(_ account: AccountDescriptor) -> String? {
        ViewStateBuilder.balanceText(of: account, snapshot: model.snapshots[account.id])
    }
}
