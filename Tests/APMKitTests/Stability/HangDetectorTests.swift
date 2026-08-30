import Testing
import Foundation
@testable import APMKit

private final class FakeHangObserving: HangObserving {
    private(set) var callback: ((HangChange, UInt64, UInt64) -> Void)?
    var returnsNilToken = false

    func addHangObserver(_ callback: @escaping (HangChange, UInt64, UInt64) -> Void) -> AnyObject? {
        self.callback = callback
        return returnsNilToken ? nil : NSObject()
    }

    func fire(_ change: HangChange, startNs: UInt64, endNs: UInt64) {
        callback?(change, startNs, endNs)
    }
}

@Suite("HangDetector — docs/02 §3.6 MOB-18")
struct HangDetectorTests {
    private let oneSecondNs: UInt64 = 1_000_000_000

    @Test("an ended hang >= threshold emits a crash/hang event, not fatal")
    func endedHangAboveThresholdEmitsEvent() {
        let observing = FakeHangObserving()
        let detector = HangDetector(observing: observing, threshold: 2.0)
        let sink = CollectingEventSink()
        detector.start(sink: sink, sessionManager: SessionManager())

        observing.fire(.ended, startNs: 0, endNs: 3 * oneSecondNs) // 3s hang

        let event = try! #require(sink.events.first)
        #expect(event.type == "crash")
        #expect(event.attrs["crash_type"] == .string("hang"))
        #expect(event.attrs["is_fatal"] == .bool(false))
        #expect(event.attrs["name"] == .string("MainThreadHang"))
        if case .string(let reason)? = event.attrs["reason"] {
            #expect(reason.contains("3000ms"))
        } else {
            Issue.record("missing reason")
        }
    }

    @Test("an ended hang below threshold (MOB-18: >2s) is ignored")
    func endedHangBelowThresholdIsIgnored() {
        let observing = FakeHangObserving()
        let detector = HangDetector(observing: observing, threshold: 2.0)
        let sink = CollectingEventSink()
        detector.start(sink: sink, sessionManager: SessionManager())

        observing.fire(.ended, startNs: 0, endNs: UInt64(1.5 * Double(oneSecondNs))) // 1.5s — below threshold

        #expect(sink.events.isEmpty)
    }

    @Test("started/updated callbacks never emit an event on their own")
    func startedAndUpdatedAreIgnored() {
        let observing = FakeHangObserving()
        let detector = HangDetector(observing: observing, threshold: 2.0)
        let sink = CollectingEventSink()
        detector.start(sink: sink, sessionManager: SessionManager())

        observing.fire(.started, startNs: 0, endNs: 0)
        observing.fire(.updated, startNs: 0, endNs: 3 * oneSecondNs)

        #expect(sink.events.isEmpty)
    }

    @Test("a boundary hang exactly at the threshold is included (>=, not >)")
    func exactlyAtThresholdIsIncluded() {
        let observing = FakeHangObserving()
        let detector = HangDetector(observing: observing, threshold: 2.0)
        let sink = CollectingEventSink()
        detector.start(sink: sink, sessionManager: SessionManager())

        observing.fire(.ended, startNs: 0, endNs: 2 * oneSecondNs) // exactly 2.0s

        #expect(sink.events.count == 1)
    }

    @Test("nil token (Watchdog monitor not installed) never crashes or throws — fails silently")
    func nilTokenFailsSilently() {
        let observing = FakeHangObserving()
        observing.returnsNilToken = true
        let detector = HangDetector(observing: observing, threshold: 2.0)
        let sink = CollectingEventSink()

        detector.start(sink: sink, sessionManager: SessionManager()) // must not throw

        observing.fire(.ended, startNs: 0, endNs: 3 * oneSecondNs)
        #expect(sink.events.count == 1) // the fake still calls back regardless of the nil token; real KSCrash wouldn't
    }

    @Test("stop() releases the token; a real observer implementation would then unregister")
    func stopReleasesToken() {
        let observing = FakeHangObserving()
        let detector = HangDetector(observing: observing, threshold: 2.0)
        detector.start(sink: CollectingEventSink(), sessionManager: SessionManager())

        detector.stop() // must not throw; nothing further to assert without a real KSCrash token
    }
}
