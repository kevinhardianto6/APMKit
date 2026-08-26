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
}
