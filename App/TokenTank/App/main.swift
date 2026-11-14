import Foundation
import TokenTankKit

#if DEBUG
if CommandLine.arguments.contains("--smoke-roundtrip") {
    let probe = "roundtrip \(Date().timeIntervalSince1970)"
    do {
        try SharedMarker.write(probe)
        let passed = SharedMarker.read() == probe
        print(passed ? "SMOKE OK" : "SMOKE FAIL: marker mismatch")
        exit(passed ? 0 : 1)
    } catch {
        print("SMOKE FAIL: \(error)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--smoke-keychain") {
    let keychain = SystemKeychain(service: "com.tokentank.smoke")
    do {
        try keychain.set("sk-smoke-secret", for: "smoke/ref")
        let readBack = keychain.key(for: "smoke/ref")
        try keychain.remove(ref: "smoke/ref")
        let passed = readBack == "sk-smoke-secret"
        print(passed ? "SMOKE OK" : "SMOKE FAIL: keychain mismatch")
        exit(passed ? 0 : 1)
    } catch {
        print("SMOKE FAIL: \(error)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--dump-snapshot") {
    // Debug: prints the stored snapshot (no secrets) and exits.
    let store = SnapshotStore(directory: AppGroup.containerURL() ?? FileManager.default.temporaryDirectory)
    guard case .file(let file) = store.read() else {
        print("DUMP: no snapshot")
        exit(0)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = (try? encoder.encode(file)) ?? Data()
    print(String(data: data, encoding: .utf8) ?? "{}")
    exit(0)
}
if CommandLine.arguments.contains("--probe-accounts") {
    // Debug: reads slot keys from the app Keychain and prints ONLY HTTP status
    // codes of the primary endpoints (never the key, never the body).
    let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    let accounts = AccountStore(defaults: defaults).accounts()
    let keychain = SystemKeychain()
    for account in accounts {
        print("== \(account.provider.rawValue) \(account.label) (region: \(account.region?.rawValue ?? "-"))")
        for slot in account.credentialSlots {
            guard let key = keychain.key(for: slot.keychainRef) else {
                print("  \(slot.id): no key in keychain")
                continue
            }
            for target in ProbeTargets.targets(for: account, slot: slot) {
                var request = URLRequest(url: target.url)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15
                let status = (try? await URLSession.shared.data(for: request))
                    .flatMap { _, response in (response as? HTTPURLResponse)?.statusCode } ?? -1
                print("  \(slot.id) \(target.name): HTTP \(status)")
            }
        }
    }
    exit(0)
}
if CommandLine.arguments.contains("--probe-raw") {
    // Debug: probes every stored apiKey slot against the URL given after the
    // flag. Status codes only; never the key.
    guard let index = CommandLine.arguments.firstIndex(of: "--probe-raw"),
          let url = CommandLine.arguments.dropFirst(index + 1).first.flatMap(URL.init(string:)) else {
        print("usage: --probe-raw <url>")
        exit(1)
    }
    let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    let accounts = AccountStore(defaults: defaults).accounts()
    let keychain = SystemKeychain()
    for account in accounts {
        for slot in account.credentialSlots where slot.kind == .apiKey {
            guard let key = keychain.key(for: slot.keychainRef) else { continue }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15
            let status = (try? await URLSession.shared.data(for: request))
                .flatMap { _, response in (response as? HTTPURLResponse)?.statusCode } ?? -1
            print("\(account.label) \(slot.id): HTTP \(status)")
        }
    }
    exit(0)
}
#endif

#if DEBUG
private struct ProbeTarget {
    let name: String
    let url: URL
}

/// Endpoint probes per provider/slot for `--probe-accounts` (status codes only).
private enum ProbeTargets {
    static func targets(for account: AccountDescriptor, slot: CredentialSlot) -> [ProbeTarget] {
        switch (account.provider, slot.kind) {
        case (.kimi, .apiKey):
            // Both regions: a 401 on one and 200 on the other pinpoints the mismatch.
            return [
                ProbeTarget(name: "balance-cn", url: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!),
                ProbeTarget(name: "balance-intl", url: URL(string: "https://api.moonshot.ai/v1/users/me/balance")!),
            ]
        case (.kimi, .coding):
            var targets = [ProbeTarget(
                name: "coding-usages",
                url: AdapterRegistry.kimiCodingBaseURL.appendingPathComponent("/v1/usages")
            )]
            if let override = slot.baseURLOverride {
                targets.append(ProbeTarget(
                    name: "coding-usages(override)",
                    url: override.appendingPathComponent("/v1/usages")
                ))
            }
            return targets
        case (.mimo, .apiKey):
            return [ProbeTarget(name: "balance", url: URL(string: "https://api.xiaomimimo.com/v1/platform/balance")!)]
        case (.mimo, .tokenPlan):
            var targets = [ProbeTarget(
                name: "token_plan(default)",
                url: URL(string: "https://token-plan-cn.xiaomimimo.com/v1/platform/token_plan")!
            )]
            if let override = slot.baseURLOverride {
                targets.append(ProbeTarget(
                    name: "token_plan(override)",
                    url: override.appendingPathComponent("/v1/platform/token_plan")
                ))
            }
            return targets
        case (.deepseek, .apiKey):
            return [ProbeTarget(name: "balance", url: URL(string: "https://api.deepseek.com/user/balance")!)]
        default:
            return []
        }
    }
}
#endif

TokenTankApp.main()
