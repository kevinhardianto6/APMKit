import Testing
import Foundation
@testable import APMKit

/// MOB-24 / VERSIONING.md: two independent manifests (`SDKInfo.current.version` and
/// `APMKit.podspec`'s `s.version`) both encode the SDK's current version, with nothing in
/// either package manager keeping them in sync automatically. This is the test VERSIONING.md
/// promises: a release that bumps one and forgets the other fails here, rather than silently
/// shipping a CocoaPods release whose `X-APM-Sdk` header (docs/01 §7/§9) reports a stale
/// version.
@Suite("Versioning — MOB-24, SDKInfo/podspec version parity")
struct VersioningTests {
    @Test("SDKInfo.current.version matches APMKit.podspec's s.version")
    func sdkInfoVersionMatchesPodspec() throws {
        let podspecURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VersioningTests.swift -> APMKitTests
            .deletingLastPathComponent() // -> Tests
            .deletingLastPathComponent() // -> repo root
            .appendingPathComponent("APMKit.podspec")
        let contents = try String(contentsOf: podspecURL, encoding: .utf8)

        let pattern = #/s\.version\s*=\s*"([^"]+)"/#
        let match = try #require(contents.firstMatch(of: pattern), "couldn't find s.version in APMKit.podspec")
        let podspecVersion = String(match.1)

        #expect(podspecVersion == SDKInfo.current.version)
    }
}
