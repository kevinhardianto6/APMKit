#if os(iOS)
import Testing
import Foundation
@testable import APMKit

/// SEC-08 (feat-014) real-Simulator verification — deliberately **not** part of the default
/// `swift test` / `./verify.sh test` run, same reasoning as `IOSCrashHarnessTests`
/// (feat-009/010). The macOS-host tests (`DiskQueueKeyStoreTests`) already prove Keychain
/// persistence *within one process* — two separate `KeychainDiskQueueKeyStore` instances, same
/// process. This two-phase harness was built to prove the scenario that actually matters
/// beyond that — **the app restarts** and needs the *same* key to decrypt what a previous
/// launch wrote — but it can only partly do that; see the finding below before relying on it.
///
/// ```
/// xcrun simctl list devices booted             # confirm a device is booted; note its UDID
/// rm -rf /tmp/apmkit-ios-encryption-harness     # start clean
///
/// xcodebuild test \
///   -scheme APMKit \
///   -destination 'platform=iOS Simulator,id=<UDID>' \
///   "-only-testing:APMKitTests/IOSDiskEncryptionHarnessTests/phaseA_writeEncrypted()"
///
/// xcodebuild test \
///   -scheme APMKit \
///   -destination 'platform=iOS Simulator,id=<UDID>' \
///   "-only-testing:APMKitTests/IOSDiskEncryptionHarnessTests/phaseB_readBackAfterRelaunch()"
/// ```
///
/// Uses a fixed `/tmp` path and a fixed Keychain service/account, for the same reason
/// `IOSCrashHarnessTests` uses `installPath` — the intent was that a fixed service/account
/// (not tied to a container) would let phase B read the key phase A wrote.
///
/// **Real finding, not the one this harness set out to prove:** it doesn't — phase B never
/// sees phase A's Keychain item, even with `xcodebuild test-without-building` reusing the
/// exact same built binary (ruling out a rebuild/re-signing explanation). Root-caused via
/// `xcrun simctl spawn ... log show --predicate 'eventMessage CONTAINS "SecItem"'`: **both**
/// phase A and phase B's very first `SecItemCopyMatching` call returns not-found, each
/// followed by a fresh `SecItemDelete`+`SecItemAdd` — i.e. Xcode's XCTest infrastructure
/// itself resets Keychain state between separate `xcodebuild test` invocations, independent of
/// app binary/container identity. This is a real constraint of *this verification tooling*,
/// not evidence about real end-user Keychain behavior (an installed app's Keychain items are
/// well-documented to survive ordinary relaunches/updates) — but this harness cannot
/// distinguish the two, and there is no sample host app in this repo (MOB-25/feat-016) to
/// install-and-relaunch for real instead. Confirming true cross-relaunch persistence needs a
/// real installed app, on a device or via `simctl install`/`launch` outside XCTest — not done
/// here; flagged on the manual verification checklist rather than claimed proven.
///
/// Given that, `phaseB_readBackAfterRelaunch` was re-scoped to verify what this harness *can*
/// honestly prove instead: that losing the key (an unavoidable, real scenario — Keychain
/// resets, device migrations, etc.) degrades safely — no crash, no thrown error into the host
/// app, the undecryptable file is silently skipped rather than corrupting the whole batch.
///
/// See `FEATURES.md` → "Manual verification checklist (pilot)" for when this was last run.
@Suite("IOSDiskEncryptionHarnessTests — manual, iOS Simulator only, not part of the default test run", .serialized)
struct IOSDiskEncryptionHarnessTests {
    private static let queueDirectory = URL(fileURLWithPath: "/tmp/apmkit-ios-encryption-harness/queue")
    private static let keychainService = "kit.apm.diskqueue-ios-harness"
    private static let keychainAccount = "encryption-key"

    private static func makeQueue() throws -> FileDiskQueue {
        let keyStore = KeychainDiskQueueKeyStore(service: keychainService, account: keychainAccount)
        let encryption = AESGCMDiskQueueEncryption(keyStore: keyStore)
        return try FileDiskQueue(directoryURL: queueDirectory, encryption: encryption)
    }

    @Test("phase A: write a real event through a real Keychain-backed encrypted queue")
    func phaseA_writeEncrypted() throws {
        let queue = try Self.makeQueue()
        try queue.enqueue(Event(
            type: "network",
            seq: 1,
            attrs: ["host": .string("very-recognizable-host-name.example.com")]
        ))

        let files = try FileManager.default.contentsOfDirectory(at: Self.queueDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let rawBytes = try #require(files.first).flatMap { try? Data(contentsOf: $0) }
        #expect(rawBytes != nil)
        #expect(!(rawBytes.map { dataContains($0, Data("very-recognizable-host-name".utf8)) } ?? true))
    }

    @Test("phase B: a fresh process that can't recover phase A's key (see the type doc's finding) degrades safely — no crash, no thrown error, the file is silently skipped")
    func phaseB_readBackAfterRelaunch() throws {
        let queue = try Self.makeQueue() // a fresh process, in practice never sees phase A's Keychain item — see the finding above

        let events = try queue.peek(limit: 10) // must not throw regardless of whether the key was recoverable

        // Documents actual behavior rather than asserting a specific outcome this harness
        // can't control: if Xcode's per-invocation Keychain reset ever stops happening, this
        // still passes (real cross-launch decryption) — if it continues, this still passes
        // (safe degradation). Either way, "did not crash and did not throw" is proven above;
        // this just records which branch actually happened, for whoever reads the test log.
        if let event = events.first(where: { $0.type == "network" }) {
            print("phase B recovered phase A's event — Keychain persisted across invocations this run: \(event.eventId)")
        } else {
            print("phase B could not recover phase A's key (expected — see this file's header comment) — the file was silently skipped, not thrown as an error")
        }
    }
}
#endif
