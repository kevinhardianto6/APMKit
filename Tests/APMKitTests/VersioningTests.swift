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

        // NSRegularExpression, not a Swift Regex literal (`firstMatch(of:)`/`Regex` need
        // iOS 16+; this SDK's floor is iOS 15) — caught by actually building this test
        // against a real iOS Simulator target (feat-014's IOSDiskEncryptionHarnessTests run),
        // not by `swift test` on the macOS host, which doesn't enforce the iOS floor here.
        let regex = try NSRegularExpression(pattern: #"s\.version\s*=\s*"([^"]+)""#)
        let nsRange = NSRange(contents.startIndex..., in: contents)
        let match = try #require(regex.firstMatch(in: contents, range: nsRange), "couldn't find s.version in APMKit.podspec")
        let versionRange = try #require(Range(match.range(at: 1), in: contents))
        let podspecVersion = String(contents[versionRange])

        #expect(podspecVersion == SDKInfo.current.version)
    }
}
