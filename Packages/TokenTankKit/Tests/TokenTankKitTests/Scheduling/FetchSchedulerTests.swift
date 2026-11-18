import Foundation
import Testing
@testable import TokenTankKit

/// Deterministic clock for scheduling tests (§9.2).
final class TestClock: Clock, @unchecked Sendable {
    var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

extension NetworkTests {
    struct FetchSchedulerTests {
        private func makeScheduler(clock: TestClock) -> FetchScheduler {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FetchSchedulerTests-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let refresher = AccountRefresher(
                keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test", "ref-admin": "sk-admin-test"]),
                store: SnapshotStore(directory: directory),
                http: stubbedHTTPClient()
            )
            return FetchScheduler(refresher: refresher, clock: clock)
        }

        private func adminAccount() -> AccountDescriptor {
            testAccount(
                provider: .kimi,
                region: .cn,
                slots: [
                    CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil),
                    CredentialSlot(id: "admin", kind: .admin, keychainRef: "ref-admin", baseURLOverride: nil),
                ]
            )
        }

        @Test func dedupSkipsWithinMinimumInterval() async throws {
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            defer { URLProtocolStub.handler = nil }
            let scheduler = makeScheduler(clock: TestClock())
            let account = testAccount(provider: .deepseek)
            #expect(await scheduler.refresh(account) == .success)
            #expect(await scheduler.refresh(account) == .skipped)
            #expect(await scheduler.refresh(account, force: true) == .success)
        }

        @Test func concurrentRefreshOfSameAccountIsSkipped() async throws {
            stubRequests { _ in
                Thread.sleep(forTimeInterval: 0.2)
                return .init(status: 200, body: fixture("deepseek-balance"))
            }
            defer { URLProtocolStub.handler = nil }
            let scheduler = makeScheduler(clock: TestClock())
            let account = testAccount(provider: .deepseek)
            async let first = scheduler.refresh(account)
            // Let the first call reach the in-flight state before the second one.
            try await Task.sleep(nanoseconds: 50_000_000)
            #expect(await scheduler.refresh(account) == .skipped)
            #expect(await first == .success)
        }

        @Test func runCyclePollsAllAccountsWithDedup() async throws {
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            defer { URLProtocolStub.handler = nil }
            let scheduler = makeScheduler(clock: TestClock())
            let accounts = [testAccount(provider: .deepseek), testAccount(provider: .deepseek)]
            let first = await scheduler.runCycle(accounts: accounts)
            #expect(first.values.allSatisfy { $0 == .success })
            let second = await scheduler.runCycle(accounts: accounts)
            #expect(second.values.allSatisfy { $0 == .skipped })
            let manual = await scheduler.runCycle(accounts: accounts, force: true)
            #expect(manual.count == accounts.count)
            #expect(manual.values.allSatisfy { $0 == .success })
        }

        @Test func concurrentRefreshesOfDifferentAccountsPreserveAllSnapshots() async throws {
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            defer { URLProtocolStub.handler = nil }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurrentRefreshTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = SnapshotStore(directory: directory)
            let scheduler = FetchScheduler(refresher: AccountRefresher(
                keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]), store: store, http: stubbedHTTPClient()
            ))
            let accounts = (0..<30).map { _ in testAccount(provider: .deepseek) }
            await withTaskGroup(of: RefreshOutcome.self) { group in
                for account in accounts {
                    group.addTask { await scheduler.refresh(account) }
                }
                for await outcome in group {
                    #expect(outcome == .success)
                }
            }
            let file = try #require({
                if case .file(let file) = store.read() { return file }
                return nil
            }())
            #expect(Set(file.accounts.map(\.accountID)) == Set(accounts.map(\.id)))
            #expect(file.accounts.allSatisfy { $0.balanceHistory?.isEmpty == false })
        }

        @Test func backoffSequenceGrowsExponentiallyAndResets() async throws {
            stubRequests { _ in .init(status: 500, body: Data()) }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let account = testAccount(provider: .deepseek)
            for attempt in 1...4 {
                let outcome = await scheduler.refresh(account)
                let expected = clock.now.addingTimeInterval(BackoffLadder.standard.delay(attempt: attempt))
                #expect(outcome == .retryAt(expected))
                clock.advance(BackoffLadder.standard.delay(attempt: attempt))
            }
            // Success resets the ladder.
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            #expect(await scheduler.refresh(account) == .success)
            stubRequests { _ in .init(status: 500, body: Data()) }
            clock.advance(301)
            let outcome = await scheduler.refresh(account)
            #expect(outcome == .retryAt(clock.now.addingTimeInterval(30)))
        }

        @Test func negativeRetryAfterFallsBackToBackoff() async throws {
            stubRequests { _ in .init(status: 429, body: Data(), headers: ["Retry-After": "-5"]) }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let account = testAccount(provider: .deepseek)
            #expect(await scheduler.refresh(account) == .retryAt(clock.now.addingTimeInterval(30)))
        }

        @Test func forceRespectsBackoff() async throws {
            stubRequests { _ in .init(status: 500, body: Data()) }
            defer { URLProtocolStub.handler = nil }
            let scheduler = makeScheduler(clock: TestClock())
            let account = testAccount(provider: .deepseek)
            guard case .retryAt = await scheduler.refresh(account) else {
                Issue.record("expected a retry outcome")
                return
            }
            #expect(await scheduler.refresh(account, force: true) == .skipped)
        }

        @Test func retryAfterHeaderIsHonored() async throws {
            stubRequests { _ in .init(status: 429, body: Data(), headers: ["Retry-After": "42"]) }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let outcome = await scheduler.refresh(testAccount(provider: .deepseek))
            #expect(outcome == .retryAt(clock.now.addingTimeInterval(42)))
        }

        @Test func invalidKeyFailsWithoutRetry() async throws {
            stubRequests { _ in .init(status: 401, body: fixture("error-generic")) }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let account = testAccount(provider: .deepseek)
            #expect(await scheduler.refresh(account) == .failed(.invalidKey))
            clock.advance(1)
            #expect(await scheduler.refresh(account) == .skipped)
        }

        @Test func dataNotReadyDefersToSevenAM() async throws {
            stubRequests { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/billings/daily_bills") || path.hasSuffix("/usage/completions") {
                    return .init(status: 400, body: fixture("kimi-admin-error-not-ready"))
                }
                return .init(status: 200, body: fixture("kimi-balance"))
            }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let outcome = await scheduler.refresh(adminAccount())
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let expected = try #require(calendar.nextDate(
                after: clock.now,
                matching: DateComponents(hour: 7, minute: 0),
                matchingPolicy: .nextTime
            ))
            #expect(outcome == .retryAt(expected))
        }

        @Test func eventRefreshRespectsDedup() async throws {
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let account = testAccount(provider: .deepseek)
            #expect(await scheduler.refresh(account) == .success)
            clock.advance(299)
            #expect(await scheduler.refresh(account) == .skipped)
            clock.advance(2)
            #expect(await scheduler.refresh(account) == .success)
        }

        @Test func adminFailuresUseKimiAdminLadder() async throws {
            stubRequests { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/billings/daily_bills") || path.hasSuffix("/usage/completions") {
                    return .init(status: 500, body: Data())
                }
                return .init(status: 200, body: fixture("kimi-balance"))
            }
            defer { URLProtocolStub.handler = nil }
            let clock = TestClock()
            let scheduler = makeScheduler(clock: clock)
            let outcome = await scheduler.refresh(adminAccount())
            #expect(outcome == .retryAt(clock.now.addingTimeInterval(1)))
        }

        @Test func toleranceIsAtLeastThirtyPercentOfInterval() {
            for interval in [300.0, 900.0, 3600.0] {
                let config = FetchScheduler.Config(interval: interval)
                #expect(config.tolerance >= interval * 0.3)
            }
            #expect(FetchScheduler.Config(interval: 60).interval == 300)
        }
    }
}
