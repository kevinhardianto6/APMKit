import Testing
import Foundation
@testable import APMKit

@Suite("ColdStartTracker — docs/01 §4.6 lifecycle, docs/02 §3.6 MOB-19")
struct ColdStartTrackerTests {
    @Test("emits a lifecycle/cold_start event with duration_ms computed from process start to the call time")
    func emitsColdStartEvent() {
        let start = Date(timeIntervalSince1970: 1_000)
        let tracker = ColdStartTracker(processStartTime: start)
        let sink = CollectingEventSink()

        tracker.recordFirstFrame(sink: sink, sessionManager: SessionManager(), now: start.addingTimeInterval(0.842))

        let event = try! #require(sink.events.first)
        #expect(event.type == "lifecycle")
        if case .string(let state)? = event.attrs["state"] {
            #expect(state == "cold_start")
        } else {
            Issue.record("missing state attr")
        }
        if case .int(let ms)? = event.attrs["duration_ms"] {
            #expect(ms == 842)
        } else {
            Issue.record("missing duration_ms attr")
        }
    }

    @Test("idempotent: a second call does nothing")
    func idempotentAcrossMultipleCalls() {
        let start = Date(timeIntervalSince1970: 1_000)
        let tracker = ColdStartTracker(processStartTime: start)
        let sink = CollectingEventSink()

        tracker.recordFirstFrame(sink: sink, sessionManager: SessionManager(), now: start.addingTimeInterval(0.1))
        tracker.recordFirstFrame(sink: sink, sessionManager: SessionManager(), now: start.addingTimeInterval(5.0))

        #expect(sink.events.count == 1)
    }

    @Test("a negative/garbage duration (clock went backwards) is never emitted")
    func neverEmitsNegativeDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let tracker = ColdStartTracker(processStartTime: start)
        let sink = CollectingEventSink()

        tracker.recordFirstFrame(sink: sink, sessionManager: SessionManager(), now: start.addingTimeInterval(-1))

        #expect(sink.events.isEmpty)
    }

    @Test("nil process start time (sysctl failed) means recordFirstFrame does nothing, never throws")
    func nilProcessStartTimeDoesNothing() {
        let tracker = ColdStartTracker(processStartTime: nil)
        let sink = CollectingEventSink()

        tracker.recordFirstFrame(sink: sink, sessionManager: SessionManager())

        #expect(sink.events.isEmpty)
    }

    @Test("currentProcessStartTime() reads a real, plausible value on this (Darwin) host")
    func realProcessStartTimeIsPlausible() throws {
        let start = try #require(ColdStartTracker.currentProcessStartTime())
        // The test process started before "now" and, generously, not more than a day ago —
        // catches a garbage sysctl read (e.g. epoch 0) without being flaky about actual timing.
        #expect(start < Date())
        #expect(Date().timeIntervalSince(start) < 24 * 60 * 60)
    }
}
