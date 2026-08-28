import Foundation

/// Reads every crash report KSCrash captured in a previous run, converts each to a `crash`
/// event (docs/01 §4.3, `CrashReportMapper`) and hands it to `sink`, then deletes the raw
/// report. Call once per launch, after `sink` (the `Scrubber`) is wired up — this is where
/// SEC-09's deferred PII scrub actually happens: the raw report may still carry unscrubbed
/// exception text (name/reason), since nothing allocation-heavy could run while it was
/// written; passing it through the same Scrub step as every other event is what makes it safe
/// before it reaches our own disk queue (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync).
public final class CrashReportProcessor {
    private let source: CrashReportSource
    private let sink: EventSink
    private let sessionManager: SessionManager

    public init(source: CrashReportSource, sink: EventSink, sessionManager: SessionManager) {
        self.source = source
        self.sink = sink
        self.sessionManager = sessionManager
    }

    public func processPendingReports() {
        for id in source.pendingReportIDs {
            defer { source.deleteReport(for: id) }
            guard let dict = source.reportDictionary(for: id),
                  let event = CrashReportMapper.makeEvent(from: dict, seq: sessionManager.nextSequenceNumber()) else {
                continue
            }
            sink.receive(event)
        }
    }
}
