import Testing
import Foundation
@testable import APMKit

private final class FakeCrashReportSource: CrashReportSource {
    var reports: [Int64: [String: Any]] = [:]
    private(set) var deletedIDs: [Int64] = []

    var pendingReportIDs: [Int64] { reports.keys.sorted() }

    func reportDictionary(for id: Int64) -> [String: Any]? { reports[id] }

    func deleteReport(for id: Int64) {
        deletedIDs.append(id)
        reports.removeValue(forKey: id)
    }
}

@Suite("CrashReportProcessor — docs/02 §3.5 MOB-15/16")
struct CrashReportProcessorTests {
    private func crashReport(signalName: String = "SIGABRT") -> [String: Any] {
        [
            "crash": [
                "error": ["type": "signal", "signal": ["name": signalName]],
                "threads": []
            ],
            "binary_images": [],
            "system": ["application_stats": ["application_in_foreground": true]],
            "report": ["timestamp": "1970-01-17T19:18:32Z"]
        ]
    }

    @Test("every pending report becomes a crash event and is deleted from the store")
    func processesAndDeletesEveryPendingReport() {
        let source = FakeCrashReportSource()
        source.reports[1] = crashReport(signalName: "SIGABRT")
        source.reports[2] = crashReport(signalName: "SIGSEGV")
        let sink = CollectingEventSink()
        let processor = CrashReportProcessor(source: source, sink: sink, sessionManager: SessionManager())

        processor.processPendingReports()

        #expect(sink.events.count == 2)
        #expect(Set(sink.events.map(\.type)) == ["crash"])
        #expect(Set(source.deletedIDs) == [1, 2])
        #expect(source.reports.isEmpty)
    }

    @Test("a report that fails to map is still deleted, never leaves the raw store lingering")
    func unmappableReportIsStillDeleted() {
        let source = FakeCrashReportSource()
        source.reports[1] = ["not_a_crash_report": true]
        let sink = CollectingEventSink()
        let processor = CrashReportProcessor(source: source, sink: sink, sessionManager: SessionManager())

        processor.processPendingReports()

        #expect(sink.events.isEmpty)
        #expect(source.deletedIDs == [1])
    }

    @Test("no pending reports means no events and nothing deleted")
    func noPendingReports() {
        let source = FakeCrashReportSource()
        let sink = CollectingEventSink()
        let processor = CrashReportProcessor(source: source, sink: sink, sessionManager: SessionManager())

        processor.processPendingReports()

        #expect(sink.events.isEmpty)
        #expect(source.deletedIDs.isEmpty)
    }

    @Test("seq numbers advance monotonically across multiple processed reports")
    func seqAdvancesAcrossReports() {
        let source = FakeCrashReportSource()
        source.reports[1] = crashReport()
        source.reports[2] = crashReport()
        let sink = CollectingEventSink()
        let sessionManager = SessionManager()
        _ = sessionManager.nextSequenceNumber() // seq 1 already consumed elsewhere in this session
        let processor = CrashReportProcessor(source: source, sink: sink, sessionManager: sessionManager)

        processor.processPendingReports()

        let seqs = Set(sink.events.map(\.seq))
        #expect(seqs == [2, 3])
    }
}
