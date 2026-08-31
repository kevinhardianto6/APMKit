import Foundation
#if canImport(KSCrashRecording)
import KSCrashRecording  // SPM: module name matches the "Recording" product
#else
import KSCrash  // CocoaPods: the KSCrash pod exposes one umbrella module, not per-subspec ones (feat-013)
#endif

/// Narrow interface over `KSCrash`'s per-key user-info API (`KSCrash+UserInfo.h`) — backed by
/// an mmap'd sidecar with zero crash-time allocation cost, unlike the deprecated bulk
/// `userInfo` dictionary. Exists so `CrashReporter`'s breadcrumb mirroring is unit-testable
/// without installing real signal/mach handlers.
public protocol CrashUserInfoStore: AnyObject {
    func setUserInfo(_ value: String?, forKey key: String)
}

extension KSCrash: CrashUserInfoStore {}
