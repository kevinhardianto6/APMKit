import Foundation

/// Tracks `session_id` (docs/01 §2: "one session = from app foreground to background >30s")
/// and the per-session monotonic `seq` counter (docs/01 §3). Background/foreground calls are
/// intended to be wired to real UIKit lifecycle notifications in feat-007; this feature only
/// implements the pure timing logic so it's directly unit-testable without waiting 30 real
/// seconds or faking notifications.
///
/// Not thread-safe by design — call from a single serial queue (the disk/sync queue feat-002
/// introduces), matching the "no blocking main-thread I/O" perf budget (docs/02 §5).
public final class SessionManager {
    public static let backgroundResetThreshold: TimeInterval = 30

    private(set) public var sessionId: String
    private var backgroundedAt: Date?
    private var seqCounter: Int = 0

    public init(initialSessionId: String = UUID().uuidString) {
        self.sessionId = initialSessionId
    }

    /// Call when the app enters background.
    public func appDidEnterBackground(at now: Date = Date()) {
        backgroundedAt = now
    }

    /// Call when the app returns to foreground. Rotates `sessionId` (and resets `seq`) only
    /// if the app was backgrounded longer than `backgroundResetThreshold`.
    public func appWillEnterForeground(at now: Date = Date()) {
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return }
        if now.timeIntervalSince(backgroundedAt) > Self.backgroundResetThreshold {
            sessionId = UUID().uuidString
            seqCounter = 0
        }
    }

    /// Next monotonic sequence number for this session (docs/01 §3, `seq`).
    public func nextSequenceNumber() -> Int {
        seqCounter += 1
        return seqCounter
    }
}
