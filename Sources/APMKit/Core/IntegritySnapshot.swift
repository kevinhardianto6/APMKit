import Foundation

/// `envelope.integrity` — docs/01 §2, requirements MOB-29/30/31.
///
/// Detection heuristics land in feat-008; this feature only defines the wire shape so the
/// envelope is complete and serializable. `.unset` is what feat-001..007 should use — all
/// `false` is indistinguishable from "checked, found nothing", so callers must not treat it
/// as a real signal until feat-008 populates it.
public struct IntegritySnapshot: Codable, Equatable {
    public var isEmulator: Bool
    public var isRooted: Bool
    public var isDevMode: Bool
    public var debuggerAttached: Bool

    enum CodingKeys: String, CodingKey {
        case isEmulator = "is_emulator"
        case isRooted = "is_rooted"
        case isDevMode = "is_dev_mode"
        case debuggerAttached = "debugger_attached"
    }

    public init(isEmulator: Bool, isRooted: Bool, isDevMode: Bool, debuggerAttached: Bool) {
        self.isEmulator = isEmulator
        self.isRooted = isRooted
        self.isDevMode = isDevMode
        self.debuggerAttached = debuggerAttached
    }

    public static let unset = IntegritySnapshot(
        isEmulator: false, isRooted: false, isDevMode: false, debuggerAttached: false
    )
}
