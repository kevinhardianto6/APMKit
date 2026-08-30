import Foundation
import APMKit

// Touches enough of the public surface — including the crash-reporting path, which is what
// actually pulls in KSCrash — that the linker can't dead-strip the SDK away and report a
// falsely small delta. Never executed; only ever built and measured on disk by
// check-binary-size-budget.sh, so it's fine that some of these calls would need a real
// backend/Keychain/Simulator to behave sensibly at runtime.

let sessionManager = SessionManager()
let diskQueue = try! FileDiskQueue(directoryURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("size-budget-queue"))
let sink = Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue))

APM.breadcrumb("size-budget probe", category: .log)
_ = APM.installCrashReporting(sink: sink, sessionManager: sessionManager)
APM.startHangDetection(sink: sink, sessionManager: sessionManager)
let configStore = RemoteConfigStore()
APM.fetchRemoteConfig(endpoint: IngestEndpoint(url: URL(string: "https://example.com/v1/ingest")!, appKey: "key"), configStore: configStore)

print("with-sdk")
