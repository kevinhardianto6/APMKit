import Foundation

/// Pure combination logic for `is_rooted`/`is_dev_mode` — deliberately separated from the
/// real OS-level probes (`DeviceIntegrityDetector`) so the *logic* ("any suspicious signal
/// means rooted") is fully unit-testable on any platform, independent of whether the
/// underlying file/symlink/receipt checks can actually run here. No `#if os(iOS)` needed —
/// this file touches no platform API at all.
enum JailbreakVerdict {
    /// docs/02 §3.8 MOB-30: file checks (Cydia/Sileo/...), a sandbox-write test, and
    /// suspicious symlinks — any one of the three is enough to call it rooted.
    static func isRooted(suspiciousFileFound: Bool, sandboxWriteSucceeded: Bool, suspiciousSymlinkFound: Bool) -> Bool {
        suspiciousFileFound || sandboxWriteSucceeded || suspiciousSymlinkFound
    }

    /// The raw sandbox-write probe (`canWriteOutsideSandbox` in `DeviceIntegrityDetector`)
    /// only means something on a real device, where the iOS sandbox normally blocks writes
    /// outside the app container — succeeding there is a genuine jailbreak signal. The
    /// Simulator runs its whole process unsandboxed on the host macOS, so the identical write
    /// would succeed on every clean Simulator too; feeding that raw `true` into `isRooted`
    /// produced a permanent false positive (every Simulator session read as rooted). This maps
    /// the raw result down to the signal `isRooted` should actually see: on Simulator the
    /// probe is discarded (treated as "did not succeed") since it can prove nothing there; on
    /// device the raw result passes through unchanged — real-device detection is untouched.
    static func sandboxWriteSignal(isSimulator: Bool, rawWriteSucceeded: Bool) -> Bool {
        isSimulator ? false : rawWriteSucceeded
    }
}

enum DevModeVerdict {
    /// docs/02 §3.8 MOB-31: a non-App-Store build is signaled by either an embedded
    /// provisioning profile (dev/ad-hoc/enterprise builds carry one; App Store builds don't)
    /// or a TestFlight/Xcode-run sandbox receipt (vs. App Store's plain "receipt").
    static func isDevMode(hasEmbeddedProvisioningProfile: Bool, hasSandboxReceipt: Bool) -> Bool {
        hasEmbeddedProvisioningProfile || hasSandboxReceipt
    }
}
