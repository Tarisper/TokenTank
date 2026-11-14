import Foundation
import TokenTankKit

// TokenTankProbe — debug-only CLI (§9.4): captures sanitized provider responses
// as test fixtures and verifies documented shapes on a live key. The key is
// read from stdin only; nothing secret is printed or written (§10).
//
// Usage:
//   TokenTankProbe mimo-sk  [--out <dir>]              # /models, balance, usage/daily, billing/daily
//   TokenTankProbe mimo-tp  [--out <dir>] [--tp-base]  # token_plan (= credits-get)
//   TokenTankProbe deepseek [--out <dir>]              # /models, /user/balance (multi-currency check)
//   TokenTankProbe kimi-cn|kimi-intl [--out <dir>]     # /v1/models, /v1/users/me/balance (+ admin probe)
//   TokenTankProbe kimi-admin [--out <dir>]            # admin usage + daily_bills (3 days)
//   TokenTankProbe kimi-coding [--out <dir>]           # coding usages + me (undocumented, §1)
//
// Verification checklist (M7 review):
//   - token_plan: period.start_at/end_at are UTC strings `YYYY-MM-DD HH:mm:ss`
//     (fix the live shape here if it differs);
//   - per-model credits: inspect the raw token_plan/usage payloads — if no
//     per-model credit fields exist, `.quota` top-model bars stay bar-less in v1.0.

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: TokenTankProbe <mimo-sk|mimo-tp|deepseek|kimi-cn|kimi-intl|kimi-admin|kimi-coding> [--out <dir>] [--tp-base <url>]")
    exit(1)
}
let mode = arguments[1]
var outDir: String?
var tpBase = "https://token-plan-cn.xiaomimimo.com"
var index = 2
while index < arguments.count {
    switch arguments[index] {
    case "--out":
        index += 1
        outDir = arguments.indices.contains(index) ? arguments[index] : nil
    case "--tp-base":
        index += 1
        tpBase = arguments.indices.contains(index) ? arguments[index] : tpBase
    default:
        break
    }
    index += 1
}

// The plan's URL convention is base without version; tolerate a trailing /v1
// so `--tp-base https://token-plan-sgp.xiaomimimo.com/v1` does not double it.
while tpBase.hasSuffix("/") {
    tpBase.removeLast()
}
if tpBase.hasSuffix("/v1") {
    tpBase.removeLast(3)
}

print("reading key from stdin…")
// Trim paste artifacts (spaces/newlines) — keys never contain whitespace.
guard let rawKey = readLine(strippingNewline: true) else {
    FileHandle.standardError.write(Data("no key on stdin\n".utf8))
    exit(1)
}
let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
guard key.isEmpty == false else {
    FileHandle.standardError.write(Data("no key on stdin\n".utf8))
    exit(1)
}

func fetch(name: String, url: URL, key: String) async {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("== \(name) [\(status)] \(url.absoluteString)")
        guard let text = String(data: data, encoding: .utf8) else {
            print("<binary>")
            return
        }
        // Sanitize before writing: an unmasked fixture never exists on disk.
        let body = SanitizedLogger.mask(text)
        print(body)
        if status == 200, let outDir {
            let dir = URL(fileURLWithPath: outDir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // `live-` prefix: captured fixtures never overwrite curated ones;
            // a human promotes them after review (§9.4).
            try Data(body.utf8).write(to: dir.appendingPathComponent("live-\(name).json"))
            print("-- fixture written: live-\(name).json")
        }
    } catch {
        print("== \(name) FAILED: \(error)")
    }
}

func day(_ offset: Int) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date().addingTimeInterval(Double(offset) * 86_400))
}

switch mode {
case "mimo-sk":
    let skBase = "https://api.xiaomimimo.com"
    await fetch(name: "mimo-models", url: URL(string: "\(skBase)/v1/models")!, key: key)
    await fetch(name: "mimo-balance", url: URL(string: "\(skBase)/v1/platform/balance")!, key: key)
    let window = "?start_date=\(day(-7))&end_date=\(day(0))"
    await fetch(name: "mimo-usage-daily", url: URL(string: "\(skBase)/v1/platform/usage/daily\(window)")!, key: key)
    await fetch(name: "mimo-billing-daily", url: URL(string: "\(skBase)/v1/platform/billing/daily\(window)")!, key: key)
case "mimo-tp":
    await fetch(name: "mimo-token-plan", url: URL(string: "\(tpBase)/v1/platform/token_plan")!, key: key)
case "deepseek":
    let base = "https://api.deepseek.com"
    await fetch(name: "deepseek-models", url: URL(string: "\(base)/models")!, key: key)
    await fetch(name: "deepseek-balance", url: URL(string: "\(base)/user/balance")!, key: key)
case "kimi-cn", "kimi-intl":
    let base = mode == "kimi-cn" ? "https://api.moonshot.cn" : "https://api.moonshot.ai"
    await fetch(name: "kimi-models", url: URL(string: "\(base)/v1/models")!, key: key)
    await fetch(name: "kimi-balance", url: URL(string: "\(base)/v1/users/me/balance")!, key: key)
    // Admin is enterprise-only: for a regular account this prints the non-2xx
    // body (evidence for the documented `unsupported` state), no fixture is saved.
    await fetch(name: "kimi-admin-probe", url: URL(string: "\(base)/v1/admin/organizations")!, key: key)
case "kimi-admin":
    let base = "https://api.moonshot.cn"
    let end = Int(Date().timeIntervalSince1970 * 1000)
    let start = end - 3 * 86_400 * 1000
    let time = "?start=\(start)&end=\(end)"
    await fetch(
        name: "kimi-admin-usage",
        url: URL(string: "\(base)/v1/admin/organizations/usage/completions\(time)&granularity=1d&limit=10")!,
        key: key
    )
    await fetch(
        name: "kimi-admin-bills",
        url: URL(string: "\(base)/v1/admin/organizations/billings/daily_bills\(time)&limit=10")!,
        key: key
    )
case "kimi-coding":
    // Undocumented endpoints (PLAN §1): capture shapes for the fail-closed parser.
    let base = "https://api.kimi.com/coding/v1"
    await fetch(name: "kimi-coding-usages", url: URL(string: "\(base)/usages")!, key: key)
    await fetch(name: "kimi-coding-me", url: URL(string: "\(base)/me")!, key: key)
default:
    FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8))
    exit(1)
}
