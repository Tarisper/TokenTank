import Foundation
import Testing
@testable import TokenTankKit

struct SanitizedLoggerTests {
    @Test func masksBearerTokens() {
        #expect(SanitizedLogger.mask("Authorization: Bearer sk-abcdef123456") == "Authorization: Bearer ***")
        #expect(SanitizedLogger.mask("Bearer abc.def-123 x") == "Bearer *** x")
    }

    @Test func masksBase64TokenTails() {
        #expect(SanitizedLogger.mask("Bearer abc+/xyz==") == "Bearer ***")
        #expect(SanitizedLogger.mask("Authorization: Bearer eyJhbGciOi+JSUzI1NiJ9.eyJzdWIi= x") == "Authorization: Bearer *** x")
    }

    @Test func masksProviderKeys() {
        #expect(SanitizedLogger.mask("key sk-1234567890 in body") == "key *** in body")
        #expect(SanitizedLogger.mask("tp-xyz") == "***")
        #expect(SanitizedLogger.mask("sk-admin-secret") == "***")
    }

    @Test func leavesPlainMessagesUntouched() {
        let message = "deepseek: balance_infos entry without currency skipped"
        #expect(SanitizedLogger.mask(message) == message)
    }
}
