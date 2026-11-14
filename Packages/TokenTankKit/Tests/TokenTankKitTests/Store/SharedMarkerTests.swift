import Foundation
import Testing
@testable import TokenTankKit

struct SharedMarkerTests {
    @Test func writeThenReadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedMarkerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = "roundtrip \(Date().timeIntervalSince1970)"
        try SharedMarker.write(probe, in: directory)
        #expect(SharedMarker.read(in: directory) == probe)
    }
}
