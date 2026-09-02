import Testing
import Foundation
@testable import APMKit

@Suite("CrashReportMapper — docs/01 §4.3 crash")
struct CrashReportMapperTests {
    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let value)? = event.attrs[key] { return value }
        return nil
    }

    private func bool(_ event: Event, _ key: String) -> Bool? {
        if case .bool(let value)? = event.attrs[key] { return value }
        return nil
    }

    private func int(_ event: Event, _ key: String) -> Int? {
        if case .int(let value)? = event.attrs[key] { return value }
        return nil
    }

    private func report(
        errorType: String,
        error: [String: Any] = [:],
        threads: [Any] = [],
        binaryImages: [Any] = [["uuid": "99E112D2-0CB4-3F73-BDA6-BCFC1F190724", "name": "MyApp"]],
        user: [String: Any] = [:],
        inForeground: Bool = true,
        activeSinceLaunch: Double = 12.5,
        backgroundSinceLaunch: Double = 0,
        timestamp: String = "1970-01-17T19:18:32Z"
    ) -> [String: Any] {
        var mergedError = error
        mergedError["type"] = errorType
        return [
            "crash": [
                "error": mergedError,
                "threads": threads
            ],
            "binary_images": binaryImages,
            "user": user,
            "system": [
                "application_stats": [
                    "application_in_foreground": inForeground,
                    "active_time_since_launch": activeSinceLaunch,
                    "background_time_since_launch": backgroundSinceLaunch
                ]
            ],
            "report": ["timestamp": timestamp]
        ]
    }

    @Test("a missing crash dictionary yields no event")
    func missingCrashDictionaryYieldsNil() {
        #expect(CrashReportMapper.makeEvent(from: [:], seq: 1) == nil)
    }

    @Test("a signal crash maps to crash_type signal, is_fatal true")
    func signalCrashMapping() throws {
        let dict = report(
            errorType: "signal",
            error: ["signal": ["name": "SIGSEGV", "signal": 11]]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 3))

        #expect(event.type == "crash")
        #expect(event.seq == 3)
        #expect(string(event, "crash_type") == "signal")
        #expect(string(event, "name") == "SIGSEGV")
        #expect(bool(event, "is_fatal") == true)
    }

    @Test("an NSException crash maps to crash_type exception, carries name/reason")
    func nsExceptionCrashMapping() throws {
        let dict = report(
            errorType: "nsexception",
            error: ["nsexception": ["name": "NSInvalidArgumentException", "reason": "unrecognized selector"]]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))

        #expect(string(event, "crash_type") == "exception")
        #expect(string(event, "name") == "NSInvalidArgumentException")
        #expect(string(event, "reason") == "unrecognized selector")
    }

    @Test("a real KSCrash 2.6.0 NSException report puts reason at the top level of error, not nested — regression for a real crash caught this")
    func realKSCrash260NSExceptionShapeReasonIsTopLevel() throws {
        // Captured verbatim (structure) from an actual `NSException(...).raise()` crash run
        // through real KSCrash 2.6.0 — the `Example-Reports/*.json` fixtures used elsewhere in
        // this suite are from an older report version that nests `reason` under
        // `error.nsexception.reason`; the real, currently-resolved dependency version does not.
        let dict = report(
            errorType: "nsexception",
            error: [
                "mach": ["exception": 10, "exception_name": "EXC_CRASH", "code": 0, "subcode": 0],
                "signal": ["signal": 6, "name": "SIGABRT", "code": 0],
                "address": 0,
                "reason": "forced crash for user 081234567890 during checkout",
                "nsexception": ["name": "HarnessTestCrash", "userInfo": NSNull()],
                "is_fatal": true,
                "is_clean_exit": false
            ]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))

        #expect(string(event, "name") == "HarnessTestCrash")
        #expect(string(event, "reason") == "forced crash for user 081234567890 during checkout")
        #expect(bool(event, "is_fatal") == true)
    }

    @Test("a resolved hang is non-fatal; an unresolved one is fatal")
    func hangFatalityMapping() throws {
        let recovered = report(errorType: "hang", error: ["hang": ["hang_recovered": true]])
        let unresolved = report(errorType: "hang", error: ["hang": ["hang_recovered": false]])

        let recoveredEvent = try #require(CrashReportMapper.makeEvent(from: recovered, seq: 1))
        let unresolvedEvent = try #require(CrashReportMapper.makeEvent(from: unresolved, seq: 1))

        #expect(string(recoveredEvent, "crash_type") == "hang")
        #expect(bool(recoveredEvent, "is_fatal") == false)
        #expect(bool(unresolvedEvent, "is_fatal") == true)
    }

    @Test("threads and binary_images round-trip as JSON strings, thread-level fields preserved (MOB-17: uuid preserved)")
    func threadsAndBinaryImagesAreJSONEncoded() throws {
        let dict = report(
            errorType: "signal",
            error: ["signal": ["name": "SIGABRT"]],
            threads: [["index": 0, "crashed": true]]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))

        let threadsJSON = try #require(string(event, "threads"))
        let decodedThreads = try JSONSerialization.jsonObject(with: Data(threadsJSON.utf8)) as? [[String: Any]]
        #expect(decodedThreads?.first?["crashed"] as? Bool == true)
        #expect(decodedThreads?.first?["index"] as? Int == 0)

        let imagesJSON = try #require(string(event, "binary_images"))
        #expect(imagesJSON.contains("99E112D2-0CB4-3F73-BDA6-BCFC1F190724"))
    }

    // MARK: - threads/binary_images reshaping to docs/01 §4.3.1/§4.3.2 (MOB-17 extension)

    /// A realistic nested fixture — KSCrash's actual shape (confirmed against
    /// `Example-Reports/*.json`): each thread is a flat dict with `backtrace.contents` holding
    /// frames, each binary image carries the full on-device path (not a basename), decimal
    /// addresses, and numeric `cpu_type`/`cpu_subtype`. `object_addr`/`instruction_addr` use
    /// docs/01 §4.3.1's own example values (`0x104a10000`/`0x104a2c810`) so the hex-formatting
    /// assertions below double as a direct check against the spec's own worked example.
    private func realisticCrashDict(appBundlePath: String = "/private/var/containers/Bundle/Application/UUID/MerchantApp.app") -> [String: Any] {
        report(
            errorType: "signal",
            error: ["signal": ["name": "SIGSEGV"]],
            threads: [
                [
                    "index": 0,
                    "crashed": true,
                    "dispatch_queue": "com.apple.main-thread",
                    "backtrace": [
                        "contents": [
                            [
                                "index": 0, "object_name": "MerchantApp",
                                "object_addr": 4372627456, "instruction_addr": 4372744208,
                                "symbol_name": "-[ViewController crash]"
                            ],
                            [
                                "index": 1, "object_name": "UIKitCore",
                                "object_addr": 4400000000, "instruction_addr": 4400012345,
                                "symbol_name": "-[UIApplication sendAction:to:from:forEvent:]"
                            ]
                        ]
                    ]
                ]
            ],
            binaryImages: [
                [
                    "name": "\(appBundlePath)/MerchantApp", "uuid": "A1B2C3D4-0000-0000-0000-000000000000",
                    "image_addr": 4372627456, "image_size": 2457600, "cpu_type": 0x0100000C, "cpu_subtype": 0
                ],
                [
                    "name": "/System/Library/Frameworks/UIKit.framework/UIKitCore", "uuid": "B2C3D4E5-0000-0000-0000-000000000000",
                    "image_addr": 4400000000, "image_size": 30000000, "cpu_type": 0x0100000C, "cpu_subtype": 0
                ]
            ]
        )
    }

    private func decodedThreads(_ event: Event) throws -> [[String: Any]] {
        let json = try #require(string(event, "threads"))
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    private func decodedImages(_ event: Event) throws -> [[String: Any]] {
        let json = try #require(string(event, "binary_images"))
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    @Test("is_app is true for a frame/binary_image inside the app's own bundle, false for a system framework — computed by the SDK from the full path, since KSCrash has already reduced object_name to a basename by the time we see it")
    func isAppComputedFromBundlePath() throws {
        let bundlePath = "/private/var/containers/Bundle/Application/UUID/MerchantApp.app"
        let event = try #require(CrashReportMapper.makeEvent(from: realisticCrashDict(appBundlePath: bundlePath), seq: 1, appBundlePath: bundlePath))
        let images = try decodedImages(event)
        let frames = try #require((try decodedThreads(event).first?["frames"]) as? [[String: Any]])

        let appImage = try #require(images.first { $0["name"] as? String == "MerchantApp" })
        let systemImage = try #require(images.first { $0["name"] as? String == "UIKitCore" })
        #expect(appImage["is_app"] as? Bool == true)
        #expect(systemImage["is_app"] as? Bool == false)

        let appFrame = try #require(frames.first { $0["object_name"] as? String == "MerchantApp" })
        let systemFrame = try #require(frames.first { $0["object_name"] as? String == "UIKitCore" })
        #expect(appFrame["is_app"] as? Bool == true)
        #expect(systemFrame["is_app"] as? Bool == false)
    }

    @Test("an app-owned embedded framework (not the main executable) is also is_app: true — matching by path containment, not by name equality with the app itself")
    func isAppTrueForAppOwnedFramework() throws {
        let dict = report(
            errorType: "signal",
            error: ["signal": ["name": "SIGSEGV"]],
            binaryImages: [
                ["name": "/private/var/containers/Bundle/Application/UUID/MerchantApp.app/Frameworks/MyFeatureKit.framework/MyFeatureKit",
                 "uuid": "C3D4E5F6-0000-0000-0000-000000000000", "image_addr": 1, "image_size": 1, "cpu_type": 0x0100000C, "cpu_subtype": 0]
            ]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1, appBundlePath: "/private/var/containers/Bundle/Application/UUID/MerchantApp.app"))
        let images = try decodedImages(event)
        #expect(images.first?["is_app"] as? Bool == true)
        #expect(images.first?["name"] as? String == "MyFeatureKit")
    }

    @Test("an empty appBundlePath never matches everything — hasPrefix(\"\") is true in Swift, which would misclassify every system binary as app-owned if not guarded")
    func emptyAppBundlePathNeverMatches() throws {
        let dict = report(errorType: "signal", error: ["signal": ["name": "SIGSEGV"]], binaryImages: [
            ["name": "/System/Library/Frameworks/UIKit.framework/UIKitCore", "uuid": "X", "image_addr": 1, "image_size": 1, "cpu_type": 0, "cpu_subtype": 0]
        ])
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1, appBundlePath: ""))
        let images = try decodedImages(event)
        #expect(images.first?["is_app"] as? Bool == false)
    }

    @Test("object_addr/instruction_addr/base_addr are formatted as lowercase 0x hex strings, matching docs/01 §4.3.1/§4.3.2's own worked example exactly")
    func addressesAreHexStrings() throws {
        let event = try #require(CrashReportMapper.makeEvent(from: realisticCrashDict(), seq: 1))
        let images = try decodedImages(event)
        let frames = try #require((try decodedThreads(event).first?["frames"]) as? [[String: Any]])

        let appImage = try #require(images.first { $0["name"] as? String == "MerchantApp" })
        #expect(appImage["base_addr"] as? String == "0x104a10000")

        let appFrame = try #require(frames.first { $0["object_name"] as? String == "MerchantApp" })
        #expect(appFrame["object_addr"] as? String == "0x104a10000")
        #expect(appFrame["instruction_addr"] as? String == "0x104a2c810")
    }

    @Test("cpu_type/cpu_subtype map to arch: arm64e when the ARM64E subtype is set, otherwise arm64 for CPU_TYPE_ARM64, x86_64 for CPU_TYPE_X86_64")
    func cpuTypeMapsToArchString() throws {
        func arch(cpuType: Int, cpuSubType: Int) throws -> String? {
            let dict = report(errorType: "signal", error: ["signal": ["name": "SIGSEGV"]], binaryImages: [
                ["name": "/x", "uuid": "X", "image_addr": 1, "image_size": 1, "cpu_type": cpuType, "cpu_subtype": cpuSubType]
            ])
            let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))
            return try decodedImages(event).first?["arch"] as? String
        }

        #expect(try arch(cpuType: 0x0100000C, cpuSubType: 0) == "arm64")
        #expect(try arch(cpuType: 0x0100000C, cpuSubType: 2) == "arm64e")
        #expect(try arch(cpuType: 0x01000007, cpuSubType: 0) == "x86_64")
    }

    @Test("binary_images name is the basename, not the full on-device path — matching docs/01 §4.3.2's example (\"MerchantApp\", not \"/private/var/.../MerchantApp.app/MerchantApp\")")
    func binaryImageNameIsBasenameNotFullPath() throws {
        let event = try #require(CrashReportMapper.makeEvent(from: realisticCrashDict(), seq: 1))
        let images = try decodedImages(event)
        #expect(images.map { $0["name"] as? String }.contains("MerchantApp"))
        #expect(!images.contains { ($0["name"] as? String)?.contains("/") == true })
    }

    @Test("symbol_name is carried through from KSCrash; file and line are always null — only the backend fills them in, post-symbolication (BE-11)")
    func fileAndLineAreAlwaysNullSymbolNameCarriesThrough() throws {
        let event = try #require(CrashReportMapper.makeEvent(from: realisticCrashDict(), seq: 1))
        let frames = try #require((try decodedThreads(event).first?["frames"]) as? [[String: Any]])
        let appFrame = try #require(frames.first { $0["object_name"] as? String == "MerchantApp" })

        #expect(appFrame["symbol_name"] as? String == "-[ViewController crash]")
        #expect(appFrame["file"] is NSNull)
        #expect(appFrame["line"] is NSNull)
    }

    @Test("thread name falls back to dispatch_queue when no pthread name was set — reproducing docs/01 §4.3.1's own example (\"com.apple.main-thread\")")
    func threadNameFallsBackToDispatchQueue() throws {
        let event = try #require(CrashReportMapper.makeEvent(from: realisticCrashDict(), seq: 1))
        let threads = try decodedThreads(event)
        #expect(threads.first?["name"] as? String == "com.apple.main-thread")
    }

    @Test("app_state derives from application_in_foreground")
    func appStateMapping() throws {
        let foreground = try #require(CrashReportMapper.makeEvent(
            from: report(errorType: "signal", error: ["signal": ["name": "SIGABRT"]], inForeground: true), seq: 1
        ))
        let background = try #require(CrashReportMapper.makeEvent(
            from: report(errorType: "signal", error: ["signal": ["name": "SIGABRT"]], inForeground: false), seq: 1
        ))

        #expect(foreground.ctx.appState == "foreground")
        #expect(background.ctx.appState == "background")
    }

    @Test("time_since_launch_ms sums active + background time, converted to ms")
    func timeSinceLaunchMapping() throws {
        let dict = report(
            errorType: "signal",
            error: ["signal": ["name": "SIGABRT"]],
            activeSinceLaunch: 1.5,
            backgroundSinceLaunch: 0.5
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))
        #expect(int(event, "time_since_launch_ms") == 2000)
    }

    @Test("an already-scrubbed breadcrumbs snapshot in the user section is carried through unchanged")
    func breadcrumbsAreCarriedThrough() throws {
        let dict = report(
            errorType: "signal",
            error: ["signal": ["name": "SIGABRT"]],
            user: ["breadcrumbs": "[{\"message\":\"tapped checkout\"}]"]
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))
        #expect(string(event, "breadcrumbs") == "[{\"message\":\"tapped checkout\"}]")
    }

    @Test("the report's own timestamp (no fractional seconds) becomes ts_client, not processing time")
    func reportTimestampIsUsed() throws {
        let dict = report(errorType: "signal", error: ["signal": ["name": "SIGABRT"]], timestamp: "1970-01-17T19:18:32Z")
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))
        #expect(event.tsClient.hasPrefix("1970-01-17T19:18:32"))
    }

    @Test(
        "a KSCrash Termination-monitor report (the SIGKILL/OOM/Xcode-Stop synthetic report) with one of the five resource-heuristic causes maps to a distinct `termination` event (docs/01 §4.7, docs/02 MOB-15b) — never `crash`",
        arguments: ["memory_limit", "memory_pressure", "cpu", "thermal", "low_battery"]
    )
    func terminationMonitorResourceKillMapsToTerminationEvent(terminationReason: String) throws {
        let dict = report(
            errorType: "termination",
            error: [
                "termination_reason": terminationReason,
                "is_fatal": true,
                "is_clean_exit": false,
                "signal": ["signal": 9, "name": "SIGKILL", "code": 0]
            ],
            activeSinceLaunch: 0.481,
            backgroundSinceLaunch: 0.1
        )
        let event = try #require(CrashReportMapper.makeEvent(from: dict, seq: 1))

        #expect(event.type == "termination")
        #expect(string(event, "termination_reason") == terminationReason)
        #expect(int(event, "time_since_launch_ms") == 581)
        #expect(event.attrs["crash_type"] == nil)
    }

    @Test(
        "a KSCrash Termination-monitor report with cause `unexplained` — or anything else unrecognized — yields no event at all: 2026-09-01 real-run finding (this used to map to crash_type signal with an empty reason, making crash-free rate falsely bad); docs/01 §4.7 explicitly drops `unexplained` since the OS gives no signal after SIGKILL to distinguish it from an ordinary dev/user termination",
        arguments: ["unexplained", "clean", "crash", "hang", "first_launch", "os_upgrade", "app_upgrade", "reboot", "none"]
    )
    func terminationMonitorNonResourceCauseYieldsNoEvent(terminationReason: String) {
        let dict = report(
            errorType: "termination",
            error: [
                "termination_reason": terminationReason,
                "is_fatal": true,
                "is_clean_exit": false,
                "signal": ["signal": 9, "name": "SIGKILL", "code": 0]
            ]
        )
        #expect(CrashReportMapper.makeEvent(from: dict, seq: 1) == nil)
    }

    @Test("a Termination-monitor report missing termination_reason entirely yields no event, not a crash")
    func terminationMonitorMissingReasonYieldsNoEvent() {
        let dict = report(errorType: "termination", error: [:])
        #expect(CrashReportMapper.makeEvent(from: dict, seq: 1) == nil)
    }
}
