import Testing
@testable import APMKit

@Suite("JailbreakVerdict / DevModeVerdict — docs/02 §3.8 MOB-30/31 combination logic")
struct IntegrityVerdictsTests {
    @Test("isRooted is true if ANY of the three signals is true", arguments: [
        (true, false, false), (false, true, false), (false, false, true),
        (true, true, true)
    ])
    func isRootedTrueIfAnySignal(signals: (Bool, Bool, Bool)) {
        #expect(JailbreakVerdict.isRooted(
            suspiciousFileFound: signals.0,
            sandboxWriteSucceeded: signals.1,
            suspiciousSymlinkFound: signals.2
        ))
    }

    @Test("isRooted is false only when all three signals are false")
    func isRootedFalseWhenNoSignals() {
        #expect(!JailbreakVerdict.isRooted(suspiciousFileFound: false, sandboxWriteSucceeded: false, suspiciousSymlinkFound: false))
    }

    @Test("isDevMode is true if EITHER signal is true", arguments: [(true, false), (false, true), (true, true)])
    func isDevModeTrueIfAnySignal(signals: (Bool, Bool)) {
        #expect(DevModeVerdict.isDevMode(hasEmbeddedProvisioningProfile: signals.0, hasSandboxReceipt: signals.1))
    }

    @Test("isDevMode is false when neither signal is true")
    func isDevModeFalseWhenNoSignals() {
        #expect(!DevModeVerdict.isDevMode(hasEmbeddedProvisioningProfile: false, hasSandboxReceipt: false))
    }
}
