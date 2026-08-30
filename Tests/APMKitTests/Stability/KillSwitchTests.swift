import Testing
import Foundation
@testable import APMKit

/// Always accepts — enough to prove *whether* an upload was attempted at all, which is what
/// this suite cares about; the response-contract matrix itself is `SyncEngineTests`' job.
private final class AlwaysAcceptUploader: IngestUploading {
    private let lock = NSLock()
    private(set) var callCount = 0

    func upload(envelope: Envelope, completion: @escaping (UploadOutcome) -> Void) {
        lock.lock(); callCount += 1; lock.unlock()
        completion(.accepted)
    }
}

/// MOB-21's actual "Done when": the user asked for this to be genuinely proven, not just
/// unit-tested per-component — one test, flipping one shared `RemoteConfigStore`, showing both
/// halves of "disables the SDK app-wide" (capture into the pipeline, and upload out of it)
/// actually stop, through the real `KillSwitch`/`Scrubber`/`FileDiskQueue`/`SyncEngine` types,
/// not fakes standing in for them.
@Suite("KillSwitch — MOB-21, proves capture AND upload actually stop")
struct KillSwitchTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KillSwitchTests-\(UUID().uuidString)")
    }

    private func trigger(_ engine: SyncEngine) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.triggerSync { continuation.resume() }
        }
    }

    @Test("disabled: nothing new reaches disk and nothing already-queued is uploaded; re-enabling resumes both")
    func killSwitchStopsCaptureAndUpload() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir)
        let configStore = RemoteConfigStore(userDefaults: UserDefaults(suiteName: "KillSwitchTests-\(UUID().uuidString)")!)
        let killSwitch = KillSwitch(downstream: Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue)), store: configStore)
        let uploader = AlwaysAcceptUploader()
        let engine = SyncEngine(
            diskQueue: diskQueue,
            uploader: uploader,
            envelopeFactory: EnvelopeFactory(sessionManager: SessionManager()),
            configuration: .init(minBackoffSeconds: 1, maxBackoffSeconds: 100, pauseDurationSeconds: 60),
            isEnabled: { configStore.current.enabled }
        )

        // 1. Enabled by default (RemoteConfig.safeDefault) — capture works normally.
        killSwitch.receive(Event(type: "network", seq: 1))
        #expect(try diskQueue.count() == 1)

        // 2. Flip the kill switch off.
        configStore.apply(RemoteConfig(enabled: false, sampling: .init(network: 1, breadcrumb: 1), maxBatch: 200, uploadIntervalSeconds: 30, disabledFeatures: []))

        // Capture stops: a new event never reaches disk.
        killSwitch.receive(Event(type: "network", seq: 2))
        #expect(try diskQueue.count() == 1) // still just the one from before disabling

        // Upload stops: the event already on disk is never sent while disabled.
        await trigger(engine)
        #expect(uploader.callCount == 0)
        #expect(try diskQueue.count() == 1) // untouched — still queued, not lost, just not sent

        // 3. Flip the kill switch back on — both resume.
        configStore.apply(RemoteConfig(enabled: true, sampling: .init(network: 1, breadcrumb: 1), maxBatch: 200, uploadIntervalSeconds: 30, disabledFeatures: []))

        killSwitch.receive(Event(type: "network", seq: 3))
        #expect(try diskQueue.count() == 2) // capture resumed

        await trigger(engine)
        #expect(uploader.callCount == 1) // upload resumed
        #expect(try diskQueue.count() == 0) // both queued events went out
    }

    @Test("dropped events from the kill switch are NOT counted by SelfHealthCounters — this is intentional suppression, not a failure")
    func killSwitchDropsAreNotSelfHealthFailures() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir)
        let selfHealth = SelfHealthCounters()
        let configStore = RemoteConfigStore(userDefaults: UserDefaults(suiteName: "KillSwitchTests-\(UUID().uuidString)")!)
        configStore.apply(RemoteConfig(enabled: false, sampling: .init(network: 1, breadcrumb: 1), maxBatch: 200, uploadIntervalSeconds: 30, disabledFeatures: []))
        let killSwitch = KillSwitch(downstream: Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue, selfHealth: selfHealth)), store: configStore)

        killSwitch.receive(Event(type: "network", seq: 1))

        let snapshot = selfHealth.snapshot()
        #expect(snapshot.dropped == 0)
        #expect(snapshot.written == 0)
    }
}
