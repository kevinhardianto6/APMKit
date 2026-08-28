import Foundation

/// Turns a breadcrumb snapshot into the JSON string mirrored into KSCrash's per-key user info
/// (`CrashReporter.startBreadcrumbMirroring`). Scrubbing happens **here**, at normal
/// breadcrumb-add time — not in the crash handler, where allocation-heavy work like regex
/// matching is unsafe (SEC-09). This is what keeps the raw on-disk crash report PII-free at
/// write time without needing crypto while the app is dying.
enum CrashBreadcrumbEncoder {
    static func scrubbedJSON(_ breadcrumbs: [Breadcrumb]) -> String {
        let scrubbed = breadcrumbs.map { breadcrumb -> Breadcrumb in
            var copy = breadcrumb
            copy.message = PatternRedactor.redact(breadcrumb.message)
            return copy
        }
        guard let data = try? JSONEncoder().encode(scrubbed), let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
