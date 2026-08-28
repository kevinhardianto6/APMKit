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

    @Test("threads and binary_images round-trip as JSON strings (MOB-17: uuid preserved)")
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

        let imagesJSON = try #require(string(event, "binary_images"))
        #expect(imagesJSON.contains("99E112D2-0CB4-3F73-BDA6-BCFC1F190724"))
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
}
