import Foundation

extension APM {
    /// Everything `APM.start(configuration:)` needs to assemble the whole pipeline in one
    /// call. Only `ingestEndpoint` is required — every other field has a safe, documented
    /// default, matching MOB-25's "under 30 minutes" integration target: the shortest correct
    /// call is `APM.start(configuration: .init(ingestEndpoint: myEndpoint))`.
    public struct Configuration {
        public var ingestEndpoint: IngestEndpoint

        /// SEC-11 (feat-015): pin material only, no `RemoteConfigStore` attached — the
        /// composition root owns the one `RemoteConfigStore` this whole pipeline shares
        /// (including this pin's own kill switch) and bundles it in internally. `nil`
        /// (default): pinning off, exactly as feat-011 alone.
        public var pinning: CertificatePinningConfiguration?

        /// `nil` (default) resolves to `<Caches>/kit.apm.queue` at `start()` time. Override
        /// only for advanced setups (e.g. a shared container) or tests.
        public var queueDirectory: URL?
        public var diskQueueConfiguration: FileDiskQueue.Configuration
        public var syncConfiguration: SyncEngine.Configuration
        /// Backing store for the `RemoteConfigStore` (MOB-20/21 cache, SEC-11's kill switch)
        /// this pipeline owns. `.standard` (default) is the correct, intentional choice for a
        /// real app — a fetched kill-switch state persisting across launches is the whole point
        /// of `RemoteConfigStore`'s own caching. Override only for tests that call `APM.start`
        /// more than once in the same process (`swift test` runs the whole suite in one
        /// process): every call sharing `.standard` would otherwise let one test's
        /// `configStore.apply(...)` leak into every other test's `APM.start()` in the same run.
        public var remoteConfigUserDefaults: UserDefaults

        public init(
            ingestEndpoint: IngestEndpoint,
            pinning: CertificatePinningConfiguration? = nil,
            queueDirectory: URL? = nil,
            diskQueueConfiguration: FileDiskQueue.Configuration = .init(),
            syncConfiguration: SyncEngine.Configuration = .init(),
            remoteConfigUserDefaults: UserDefaults = .standard
        ) {
            self.ingestEndpoint = ingestEndpoint
            self.pinning = pinning
            self.queueDirectory = queueDirectory
            self.diskQueueConfiguration = diskQueueConfiguration
            self.syncConfiguration = syncConfiguration
            self.remoteConfigUserDefaults = remoteConfigUserDefaults
        }

        /// `<Caches>/kit.apm.queue` — `.cachesDirectory` because this queue is APM Kit's own
        /// operational data, not something the user should ever see or a backup should ever
        /// carry (`FileDiskQueue` already excludes it from backup independently, SEC-07); a
        /// missing caches URL falls back to `.temporaryDirectory` rather than force-unwrapping
        /// (`CONSTITUTION.md`: no force unwraps in SDK code) — practically unreachable on iOS,
        /// but this code also runs on the macOS host toolchain (`swift test`).
        public static func defaultQueueDirectory() -> URL {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return base.appendingPathComponent("kit.apm.queue", isDirectory: true)
        }
    }
}
