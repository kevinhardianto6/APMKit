import Foundation

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
    /// host tidak mengisinya, SDK meng-generate ID acak stabil per install").
    public static func currentUserId(userDefaults: UserDefaults = .standard) -> String {
        if let explicit = userDefaults.string(forKey: explicitKey) {
            return explicit
        }
        if let fallback = userDefaults.string(forKey: fallbackKey) {
            return fallback
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: fallbackKey)
        return generated
    }
}
