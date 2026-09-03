import Foundation

/// `envelope.user_id_source` — docs/01 §2.2, MOB-28 extended. Without this, an app that never
/// wires `setUser` is invisible: its sessions still produce a `user_id` (the generated
/// fallback), so User Lookup returns data that looks normal but can never be correlated to a
/// real user — and nobody notices, because nothing distinguishes it from a host-set id.
public enum UserIdSource: String, Codable, Equatable {
    case host
    case generated
}

/// `envelope.user_id` — docs/01 §2.1, MOB-28, SEC-06.
///
/// **The raw value is sent as-is, never hashed or validated client-side.** Hashing to the
/// opaque `user_ref` is exclusively the backend's job at ingestion (BE-21) — the SDK's only
/// obligation is that this raw value occupies exactly the `user_id` envelope slot and never
/// leaks anywhere else (breadcrumbs, logs, other event attrs). App hosts may set literally
/// any string here (phone number, email, internal id, ...); the SDK does not inspect it.
///
/// Mirrors `InstallIdentity`'s style (enum of static functions over `UserDefaults`) — same
/// persistence pattern, deliberately a *separate* key from `install_id`: they answer
/// different questions (device install vs. user identity) even though both fall back to a
/// stable-per-install random value when nothing else is available.
public enum UserIdentity {
    private static let explicitKey = "kit.apm.user_id.explicit"
    private static let fallbackKey = "kit.apm.user_id.fallback"

    /// Sets the raw `user_id`. Accepts any non-empty string — no validation, no hashing.
    public static func setUser(id: String, userDefaults: UserDefaults = .standard) {
        userDefaults.set(id, forKey: explicitKey)
    }

    /// The raw `user_id` for the next envelope: the explicitly-set value if any, otherwise a
    /// stable random id generated once and persisted per install (docs/01 §2: "Kalau app
    /// host tidak mengisinya, SDK meng-generate ID acak stabil per install"). Implemented in
    /// terms of `currentUserIdentity` so the two can never disagree about which branch fired.
    public static func currentUserId(userDefaults: UserDefaults = .standard) -> String {
        currentUserIdentity(userDefaults: userDefaults).id
    }

    /// `user_id` and `user_id_source` (docs/01 §2.2), computed together in one pass over
    /// `UserDefaults` — reading them via two separate calls could, in principle, straddle a
    /// `setUser` call landing in between and report an id/source pair that never actually
    /// co-occurred. `EnvelopeFactory` uses this, not `currentUserId` alone.
    public static func currentUserIdentity(userDefaults: UserDefaults = .standard) -> (id: String, source: UserIdSource) {
        if let explicit = userDefaults.string(forKey: explicitKey) {
            return (explicit, .host)
        }
        if let fallback = userDefaults.string(forKey: fallbackKey) {
            return (fallback, .generated)
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: fallbackKey)
        return (generated, .generated)
    }
}
