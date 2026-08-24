import Foundation

/// `envelope.install_id` — docs/01 §2. Generated once, persisted for the life of the
/// install, reset when the app is uninstalled. `UserDefaults` is removed by the OS on
/// uninstall, which is exactly the reset behavior the spec asks for.
public enum InstallIdentity {
    private static let key = "kit.apm.install_id"

    public static func current(userDefaults: UserDefaults = .standard) -> String {
        if let existing = userDefaults.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: key)
        return generated
    }
}
