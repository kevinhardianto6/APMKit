import Foundation
import KSCrashRecording

/// Narrow interface over `CrashReportStore`, so `CrashReportProcessor` is unit-testable
/// without a real on-disk KSCrash store.
public protocol CrashReportSource {
    var pendingReportIDs: [Int64] { get }
    func reportDictionary(for id: Int64) -> [String: Any]?
    func deleteReport(for id: Int64)
}

/// Adapts KSCrash's real report store (`KSCrash.shared.reportStore`) to `CrashReportSource`.
public final class KSCrashReportSource: CrashReportSource {
    private let store: CrashReportStore

    public init(store: CrashReportStore) {
        self.store = store
    }

    public var pendingReportIDs: [Int64] {
        store.reportIDs.map { $0.int64Value }
    }

    public func reportDictionary(for id: Int64) -> [String: Any]? {
        store.report(for: id)?.value
    }

    public func deleteReport(for id: Int64) {
        store.deleteReport(with: id)
    }
}
