import Testing
import Foundation
@testable import APMKit

private struct SampleError: Error, LocalizedError {
    var errorDescription: String? { "something went wrong" }
}

@Suite("ManualReporter — docs/01 §4.4 error, docs/02 §3.4 MOB-11")
struct ManualReporterTests {
    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let value)? = event.attrs[key] { return value }
        return nil
    }

    private func int(_ event: Event, _ key: String) -> Int? {
        if case .int(let value)? = event.attrs[key] { return value }
        return nil
    }

    @Test("logError produces an error event with handled always true")
    func logErrorProducesErrorEvent() {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        reporter.logError(SampleError())

        #expect(sink.events.count == 1)
        let event = sink.events[0]
        #expect(event.type == "error")
        if case .bool(let handled)? = event.attrs["handled"] {
            #expect(handled == true)
        } else {
            Issue.record("expected a bool handled attribute")
        }
        #expect(string(event, "message") == "something went wrong")
    }

    @Test("custom context keys are prefixed with custom. and included")
    func customContextIsIncluded() {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        reporter.logError(SampleError(), context: ["screen": "Checkout", "step": "payment"])

        let event = sink.events[0]
        #expect(string(event, "custom.screen") == "Checkout")
        #expect(string(event, "custom.step") == "payment")
    }

    @Test("context is capped at 20 keys and 256 chars per value (docs/01 §4.4)")
    func contextIsCapped() {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        var context: [String: String] = [:]
        for i in 0..<30 { context["key\(i)"] = "value\(i)" }
        context["longValue"] = String(repeating: "x", count: 1000)

        reporter.logError(SampleError(), context: context)

        let event = sink.events[0]
        let customKeys = event.attrs.keys.filter { $0.hasPrefix("custom.") }
        #expect(customKeys.count <= 20)
        if let longValue = string(event, "custom.longValue") {
            #expect(longValue.count <= 256)
        }
    }

    // MARK: - Breadcrumb attachment (MOB-13)

    @Test("logError attaches a JSON snapshot of the breadcrumb ring buffer")
    func logErrorAttachesBreadcrumbSnapshot() throws {
        let sink = CollectingEventSink()
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        buffer.add(Breadcrumb(category: .navigation, message: "OrderScreen"))
        buffer.add(Breadcrumb(category: .userAction, message: "tapped checkout"))
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager(), breadcrumbs: buffer)

        reporter.logError(SampleError())

        let json = try #require(string(sink.events[0], "breadcrumbs"))
        let decoded = try JSONDecoder().decode([Breadcrumb].self, from: Data(json.utf8))
        #expect(decoded.map(\.message) == ["OrderScreen", "tapped checkout"])
        #expect(decoded.map(\.category) == [.navigation, .userAction])
    }

    @Test("with no breadcrumbs recorded, the snapshot is an empty JSON array, not an error")
    func logErrorWithNoBreadcrumbsAttachesEmptyArray() throws {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager(), breadcrumbs: BreadcrumbRingBuffer(capacity: 100))

        reporter.logError(SampleError())

        let json = try #require(string(sink.events[0], "breadcrumbs"))
        let decoded = try JSONDecoder().decode([Breadcrumb].self, from: Data(json.utf8))
        #expect(decoded.isEmpty)
    }

    // MARK: - Call-site capture (docs/01 §4.4, docs/02 MOB-11b)

    @Test("logError auto-captures source_file using the #fileID short form — no leading slash, no /Users/ segment. This is the regression #file would silently reintroduce (SEC-05b: #file leaks the build machine's username and directory layout, and SEC-05's phone/email/JWT scrubbing patterns would not catch it)")
    func sourceFileUsesFileIDShortFormNotAbsolutePath() throws {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        reporter.logError(SampleError())

        let sourceFile = try #require(string(sink.events[0], "source_file"))
        #expect(!sourceFile.hasPrefix("/"))
        #expect(!sourceFile.contains("/Users/"))
        // #fileID's own documented shape: "Module/File.swift".
        #expect(sourceFile.hasSuffix(".swift"))
        #expect(sourceFile.contains("/"))
    }

    @Test("logError auto-captures source_function and source_line at the actual call site, with no developer input")
    func sourceFunctionAndLineAreCaptured() {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        let expectedLine = #line + 1
        reporter.logError(SampleError())

        let event = sink.events[0]
        #expect(string(event, "source_function") == #function)
        #expect(int(event, "source_line") == expectedLine)
    }

    @Test("an explicit file/function/line (as a wrapper forwarding its own call site would pass) overrides the default capture")
    func explicitSourceLocationOverridesDefault() {
        let sink = CollectingEventSink()
        let reporter = ManualReporter(sink: sink, sessionManager: SessionManager())

        reporter.logError(SampleError(), file: "Module/Forwarded.swift", function: "forwardedFunction()", line: 42)

        let event = sink.events[0]
        #expect(string(event, "source_file") == "Module/Forwarded.swift")
        #expect(string(event, "source_function") == "forwardedFunction()")
        #expect(int(event, "source_line") == 42)
    }
}
