import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `envelope.device` — docs/01 §2.
///
/// Gathering real values needs `UIDevice`, which is iOS-only. The `#else` branch exists
/// only so this target still compiles/tests on the host macOS toolchain via `swift test`
/// (see AGENTS.md → Verification); the SDK itself only ever ships on iOS.
public struct DeviceInfo: Codable, Equatable {
    public var os: String
    public var osVersion: String
    public var model: String
    public var locale: String
    public var timezone: String

    enum CodingKeys: String, CodingKey {
        case os
        case osVersion = "os_version"
        case model, locale, timezone
    }

    public init(os: String, osVersion: String, model: String, locale: String, timezone: String) {
        self.os = os
        self.osVersion = osVersion
        self.model = model
        self.locale = locale
        self.timezone = timezone
    }

    public static func current() -> DeviceInfo {
        #if canImport(UIKit)
        return DeviceInfo(
            os: "iOS",
            osVersion: UIDevice.current.systemVersion,
            model: hardwareModelIdentifier(),
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        #else
        return DeviceInfo(
            os: "iOS",
            osVersion: "unknown",
            model: "unknown",
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        #endif
    }

    /// Raw machine identifier, e.g. `"iPhone14,2"` — matches the example in docs/01 §2.
    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial += String(UnicodeScalar(UInt8(value)))
        }
    }
}
