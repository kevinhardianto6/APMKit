import Testing
import Darwin
@testable import APMKit

/// `#if canImport(Darwin)` — `sysctl`/`P_TRACED` are Darwin-specific, but Darwin covers both
/// iOS and this test host (macOS), so `isDebuggerAttached`'s bit-check logic is genuinely
/// testable here. `isEmulator`/`isRooted`/`isDevMode` are not — see each test's comment for
/// exactly what is and isn't proven by running this suite via `swift test` on macOS.
@Suite("DeviceIntegrityDetector — docs/01 §2, docs/02 §3.8 MOB-29/30/31")
struct DeviceIntegrityDetectorTests {
    @Test("isDebuggerAttached is true when P_TRACED is set in the process flags")
    func debuggerAttachedTrueWhenTracedBitSet() {
        #expect(DeviceIntegrityDetector.isDebuggerAttached(processFlags: { P_TRACED }))
    }

    @Test("isDebuggerAttached is false when P_TRACED is not set")
    func debuggerAttachedFalseWhenTracedBitUnset() {
        #expect(!DeviceIntegrityDetector.isDebuggerAttached(processFlags: { 0 }))
    }

    @Test("isDebuggerAttached only looks at the P_TRACED bit, ignoring unrelated flag bits")
    func debuggerAttachedIgnoresUnrelatedBits() {
        let unrelatedFlags: Int32 = 0x0001 | 0x0004 // arbitrary bits that aren't P_TRACED
        #expect(!DeviceIntegrityDetector.isDebuggerAttached(processFlags: { unrelatedFlags }))
        #expect(DeviceIntegrityDetector.isDebuggerAttached(processFlags: { unrelatedFlags | P_TRACED }))
    }

    @Test("isEmulator() compiles and runs — correct by construction (#if targetEnvironment(simulator)), but its true branch is NOT exercised by a macOS swift test run (only real Simulator/xcodebuild can)")
    func isEmulatorRunsWithoutCrashing() {
        // On this host (macOS, not built for iOS Simulator), this MUST be false — proving
        // the false branch, not the true one. See DeviceIntegrityDetector's doc comment.
        #expect(DeviceIntegrityDetector.isEmulator() == false)
    }

    @Test("isRooted()/isDevMode() on the macOS host toolchain hit their non-iOS fallback (always false) — this proves the fallback exists and compiles, NOT that real jailbreak/dev-mode detection works (needs a real device/simulator)")
    func rootedAndDevModeFallbackOnHost() {
        #expect(DeviceIntegrityDetector.isRooted() == false)
        #expect(DeviceIntegrityDetector.isDevMode() == false)
    }

    @Test("snapshot() wires all four probes into one IntegritySnapshot")
    func snapshotWiresAllFourProbes() {
        let snapshot = DeviceIntegrityDetector.snapshot()
        // On this host: isEmulator/isRooted/isDevMode are all false (see tests above for why);
        // debuggerAttached reflects whatever this actual test-runner process's P_TRACED bit
        // is (true if literally run under a debugger) — just confirm it doesn't crash and
        // produces a well-formed snapshot, not a specific value.
        #expect(snapshot.isEmulator == false)
        #expect(snapshot.isRooted == false)
        #expect(snapshot.isDevMode == false)
    }
}
