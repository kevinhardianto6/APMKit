import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// `envelope.integrity` — docs/01 §2, docs/02 §3.8 (MOB-29/30/31). Snapshotted once per
/// session (caching lives in `SessionManager`, invalidated on session rotation — see its
/// `currentIntegritySnapshot()`), not recomputed per event.
///
/// **Heuristic only, by design — this is observability, not a security gate.** Every check
/// here can be defeated by a sufficiently motivated device (Magisk DenyList and friends); the
/// point is filtering non-real sessions out of aggregate metrics, not blocking anything. No
/// privileged/restricted APIs are used (no IMEI, no serial number) — every probe below is
/// something any app can already call. Do not add attestation (App Attest/DeviceCheck) here;
/// that's an explicit post-v1 decision (docs/00 §11).
///
/// **Host-toolchain honesty:** `isRooted()`/`isDevMode()`'s real file/symlink/receipt probes
/// only compile under `#if os(iOS)` and return `false` unconditionally elsewhere — `swift
/// test` on macOS cannot exercise the real detection logic at all, only the pure
/// `JailbreakVerdict`/`DevModeVerdict` combination rules those probes feed into. `isEmulator()`
/// is correct by construction (`#if targetEnvironment(simulator)`) but its `true` branch
/// likewise can't be exercised by `swift test` on a macOS host, which never compiles for
/// Simulator. Real-device + Simulator verification is a manual step for the pilot, not
/// something to fake in automated tests.
///
/// **Simulator false positive (2026-09-01 real-run finding):** the pilot ingestion server
/// showed every clean Simulator session reporting `is_rooted = true`. Cause: the Simulator
/// runs as an ordinary unsandboxed macOS process, so `canWriteOutsideSandbox()`'s write to
/// `/private/...` structurally always succeeds there — a signal that means "jailbroken" only
/// on a real device, where the sandbox is real and would normally block it. That raw `true`
/// was feeding straight into `JailbreakVerdict.isRooted`'s OR-combination. Fixed by having
/// `isRooted()` route the raw write result through `JailbreakVerdict.sandboxWriteSignal`,
/// which discards it (treats it as "did not succeed") specifically on Simulator and passes it
/// through unchanged on device — device detection is not weakened. **What this can and can't
/// prove:** the file/symlink probes are left untouched here because a stock Simulator
/// filesystem doesn't carry jailbreak tooling and a hit there would still be a real (if
/// theoretical) signal, not a structural false positive like the sandbox-write probe was — but
/// that's an argument from how Simulator's filesystem happens to be laid out today, not a
/// proof; only a real Simulator/device run (`FEATURES.md` manual checklist item 1) can confirm
/// `is_rooted` actually reads `false` end-to-end. `swift test` on the macOS host can't
/// exercise any of this either way, clean or rooted — it never compiles the `#if os(iOS)`
/// branch at all, so the unit test for this fix targets only the pure `sandboxWriteSignal`
/// mapping, not the live Simulator probe.
public enum DeviceIntegrityDetector {
    public static func snapshot() -> IntegritySnapshot {
        IntegritySnapshot(
            isEmulator: isEmulator(),
            isRooted: isRooted(),
            isDevMode: isDevMode(),
            debuggerAttached: isDebuggerAttached()
        )
    }

    // MARK: - is_emulator (MOB-29)

    static func isEmulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - is_rooted (MOB-30)

    #if os(iOS)
    private static let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Applications/Installer.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/Library/MobileSubstrate/DynamicLibraries",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt",
        "/private/var/lib/cydia",
        "/private/var/stash",
        "/usr/libexec/cydia",
        "/usr/bin/ssh"
    ]

    /// Directories that are plain folders on a stock filesystem but get symlinked to
    /// `/private/var/stash` by classic jailbreak tools to work around read-only system
    /// partition restrictions.
    private static let symlinkCheckPaths = [
        "/Applications",
        "/Library/Ringtones",
        "/Library/Wallpaper",
        "/usr/include",
        "/usr/libexec",
        "/usr/share"
    ]

    static func isRooted(fileManager: FileManager = .default) -> Bool {
        JailbreakVerdict.isRooted(
            suspiciousFileFound: suspiciousPaths.contains { fileManager.fileExists(atPath: $0) },
            sandboxWriteSucceeded: JailbreakVerdict.sandboxWriteSignal(
                isSimulator: isEmulator(),
                rawWriteSucceeded: canWriteOutsideSandbox()
            ),
            suspiciousSymlinkFound: symlinkCheckPaths.contains { isSymlink($0, fileManager: fileManager) }
        )
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/apmkit-integrity-check-\(UUID().uuidString)"
        do {
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private static func isSymlink(_ path: String, fileManager: FileManager) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }
    #else
    static func isRooted() -> Bool { false }
    #endif

    // MARK: - is_dev_mode (MOB-31: non-App-Store build)

    #if os(iOS)
    static func isDevMode(bundle: Bundle = .main) -> Bool {
        DevModeVerdict.isDevMode(
            hasEmbeddedProvisioningProfile: hasEmbeddedProvisioningProfile(bundle: bundle),
            hasSandboxReceipt: hasSandboxReceipt(bundle: bundle)
        )
    }

    private static func hasEmbeddedProvisioningProfile(bundle: Bundle) -> Bool {
        bundle.path(forResource: "embedded", ofType: "mobileprovision") != nil
    }

    private static func hasSandboxReceipt(bundle: Bundle) -> Bool {
        bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    #else
    static func isDevMode() -> Bool { false }
    #endif

    // MARK: - debugger_attached (MOB-31: sysctl P_TRACED)

    /// `processFlags` is injectable so the bit-check logic is testable without needing an
    /// actual attached debugger — real callers use the default, which reads the live
    /// process's `kinfo_proc` via `sysctl`. Portable (Darwin's BSD-derived `sysctl` exists on
    /// macOS too), unlike the jailbreak/dev-mode probes above.
    static func isDebuggerAttached(processFlags: () -> Int32 = currentProcessFlags) -> Bool {
        #if canImport(Darwin)
        (processFlags() & P_TRACED) != 0
        #else
        false
        #endif
    }

    #if canImport(Darwin)
    private static func currentProcessFlags() -> Int32 {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Int32(info.kp_proc.p_flag)
    }
    #endif
}
