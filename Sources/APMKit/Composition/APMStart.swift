import Foundation

extension APM {
    /// The composition root (feat-016, MOB-25's integration-time risk). Assembles and wires
    /// the entire pipeline these already-shipped pieces produce — `SessionManager`,
    /// `FileDiskQueue` (encrypted by default, SEC-08), the `KillSwitch → Scrubber →
    /// DiskQueueEventSink` chain (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync),
    /// `EnvelopeFactory`, `IngestClient`/`SyncEngine` with its background/connectivity triggers
    /// wired to real `UIApplication`/`NWPathMonitor` notifications (via
    /// `AutomaticBreadcrumbSource`'s hooks, not a second competing observer), crash reporting,
    /// hang detection, and an initial remote-config fetch — by construction, in one call,
    /// rather than documentation asking an integrator to remember roughly a dozen steps in the
    /// right order (`FEATURES.md`'s own framing: the same "make forgetting structurally
    /// impossible" shape as feat-005's anti-loop guarantee and feat-009's pending-crash-report
    /// drain, applied to the whole integration instead of one leak at a time).
    ///
    /// Every granular type this method wires (`SessionManager`, `FileDiskQueue`, `IngestClient`,
    /// `SyncEngine`, every other `APM.*` call, ...) **stays public** — this is an additive
    /// convenience layer for the common case, not a replacement that locks out custom
    /// pipelines.
    ///
    /// Never throws (`CONSTITUTION.md` rule #1): `FileDiskQueue.init`'s only failure mode
    /// (can't create its directory) falls back to `EphemeralInMemoryDiskQueue` rather than
    /// propagating — a degraded pipeline (events don't survive a process death) instead of no
    /// pipeline or a crash.
    ///
    /// Call once, as early as possible during app launch (matching every individual piece's own
    /// existing "call once, at launch" documentation) — main thread is fine, the only
    /// synchronous work here is in-memory object construction and `FileDiskQueue`'s directory
    /// creation; KSCrash installation is itself synchronous by its own design (fast, no heavy
    /// work on the launch path — see `CrashReporter.install`), and crash-report draining,
    /// hang-detector registration, and the remote-config fetch are all either already
    /// backgrounded internally or fire-and-forget network calls.
    @discardableResult
    public static func start(configuration: Configuration) -> APMInstance {
        let sessionManager = SessionManager()
        let configStore = RemoteConfigStore(userDefaults: configuration.remoteConfigUserDefaults)

        let diskQueue: DiskQueue
        do {
            diskQueue = try FileDiskQueue(
                directoryURL: configuration.queueDirectory ?? Configuration.defaultQueueDirectory(),
                configuration: configuration.diskQueueConfiguration
            )
        } catch {
            diskQueue = EphemeralInMemoryDiskQueue()
        }

        // Capture → Scrub → Disk (CONSTITUTION.md), KillSwitch outermost (feat-010: zero work,
        // not even scrubbing, the moment the SDK is remotely disabled).
        let diskSink = DiskQueueEventSink(diskQueue: diskQueue)
        let scrubber = Scrubber(downstream: diskSink)
        let sink: EventSink = KillSwitch(downstream: scrubber, store: configStore)

        // SEC-11 (feat-015): bundles the pin material with THIS pipeline's one RemoteConfigStore
        // — the host never constructs or sees a RemoteConfigStore just to enable pinning.
        let pinning = configuration.pinning.map {
            CertificatePinning(configuration: $0, remoteConfigStore: configStore)
        }

        let ingestClient = IngestClient(endpoint: configuration.ingestEndpoint, pinning: pinning)
        let envelopeFactory = EnvelopeFactory(sessionManager: sessionManager)
        let syncEngine = SyncEngine(
            diskQueue: diskQueue,
            uploader: ingestClient,
            envelopeFactory: envelopeFactory,
            configuration: configuration.syncConfiguration,
            isEnabled: { [weak configStore] in configStore?.current.enabled ?? true }
        )
        syncEngine.start() // MOB-08 trigger 1/3: the periodic timer

        // MOB-15/16/17: install (synchronous) + drain previous run's pending reports
        // (backgrounded internally by `installCrashReporting` itself).
        installCrashReporting(sink: sink, sessionManager: sessionManager)
        // MOB-18: requires the Watchdog monitor `installCrashReporting` just enabled above —
        // order matters, this must come after, not before.
        startHangDetection(sink: sink, sessionManager: sessionManager)

        // MOB-20: seeds `configStore` beyond whatever it cached from a previous launch —
        // fire-and-forget, `RemoteConfigStore` is already synchronously usable before this
        // call returns (seeded from cache/.safeDefault at its own init).
        fetchRemoteConfig(endpoint: configuration.ingestEndpoint, configStore: configStore, pinning: pinning)

        // MOB-08 triggers 2/3 and 3/3 (background transition, connectivity restore) — wired
        // through AutomaticBreadcrumbSource's own real UIApplication/NWPathMonitor observers
        // rather than a second, duplicate set. Also gives automatic breadcrumbs (feat-007) for
        // free as part of the one-call happy path, since nothing else in this pipeline turns
        // that already-shipped feature on.
        let breadcrumbSource = AutomaticBreadcrumbSource()
        breadcrumbSource.onDidEnterBackground = { [weak sessionManager, weak syncEngine] in
            sessionManager?.appDidEnterBackground()
            syncEngine?.appDidEnterBackground()
        }
        breadcrumbSource.onWillEnterForeground = { [weak sessionManager] in
            sessionManager?.appWillEnterForeground()
        }
        breadcrumbSource.onConnectivityRestored = { [weak syncEngine] in
            syncEngine?.connectivityRestored()
        }
        breadcrumbSource.start()

        return APMInstance(
            sink: sink,
            sessionManager: sessionManager,
            configStore: configStore,
            syncEngine: syncEngine,
            ingestEndpoint: configuration.ingestEndpoint,
            breadcrumbSource: breadcrumbSource
        )
    }
}
