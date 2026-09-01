import Foundation

/// Returned by `APM.start(configuration:)` — holds the pipeline pieces most call sites need
/// after startup, and forwards to the existing granular static `APM.*` methods so a host using
/// `start()` never has to thread `sink`/`sessionManager` through its own call sites by hand.
/// The granular statics themselves are unchanged and still directly callable for advanced/
/// custom setups that don't use `APM.start` at all — this type is an additive convenience
/// layer, not a replacement.
public final class APMInstance {
    /// The fully-wired pipeline entry point: `KillSwitch → Scrubber → DiskQueueEventSink`
    /// (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync). Exposed for advanced callers who
    /// need to feed a custom capture path into the same pipeline `instrumentedSession`/
    /// `logError` already use.
    public let sink: EventSink
    public let sessionManager: SessionManager
    public let configStore: RemoteConfigStore
    public let syncEngine: SyncEngine
    private let ingestEndpoint: IngestEndpoint
    /// Held so its observers/`NWPathMonitor` live as long as this instance — releasing
    /// `APMInstance` stops automatic breadcrumbs and the background/connectivity triggers this
    /// wires into `sessionManager`/`syncEngine`, same lifecycle rule `AutomaticBreadcrumbSource`
    /// already documents for itself.
    private let breadcrumbSource: AutomaticBreadcrumbSource

    init(
        sink: EventSink,
        sessionManager: SessionManager,
        configStore: RemoteConfigStore,
        syncEngine: SyncEngine,
        ingestEndpoint: IngestEndpoint,
        breadcrumbSource: AutomaticBreadcrumbSource
    ) {
        self.sink = sink
        self.sessionManager = sessionManager
        self.configStore = configStore
        self.syncEngine = syncEngine
        self.ingestEndpoint = ingestEndpoint
        self.breadcrumbSource = breadcrumbSource
    }

    /// Forwards to `APM.instrumentedSession` with this instance's `sink`/`sessionManager`/
    /// `ingestEndpoint` already filled in — the anti-loop exclusion (MOB-09/10) still happens
    /// automatically, same as the static method.
    public func instrumentedSession(
        configuration: URLSessionConfiguration = .default,
        additionalExcludedHosts: Set<String> = [],
        pinningDelegate: NetworkCaptureForwardingDelegate? = nil
    ) -> (session: URLSession, captureDelegate: NetworkCaptureDelegate) {
        APM.instrumentedSession(
            configuration: configuration,
            sink: sink,
            sessionManager: sessionManager,
            ingestEndpoint: ingestEndpoint,
            additionalExcludedHosts: additionalExcludedHosts,
            pinningDelegate: pinningDelegate
        )
    }

    /// Forwards to `APM.logError` with this instance's `sink`/`sessionManager` already filled
    /// in. `file`/`function`/`line` (docs/02 MOB-11b) default to `#fileID`/`#function`/`#line`
    /// evaluated at the app's actual call site — this is the entry point most hosts call, so
    /// forwarding these explicitly (rather than letting `APM.logError`'s own defaults fire) is
    /// what keeps `source_file` pointing at the app, not at this file.
    public func logError(
        _ error: Error,
        context: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        APM.logError(error, context: context, sink: sink, sessionManager: sessionManager, file: file, function: function, line: line)
    }

    /// Forwards to `APM.recordFirstFrame` with this instance's `sink`/`sessionManager` already
    /// filled in. Still host-invoked, not automatic — see `ColdStartTracker`'s doc comment for
    /// why "first frame drawn" can't be detected generically.
    public func recordFirstFrame() {
        APM.recordFirstFrame(sink: sink, sessionManager: sessionManager)
    }
}
