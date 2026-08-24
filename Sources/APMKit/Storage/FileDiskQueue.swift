import Foundation

/// File-per-event `DiskQueue` implementation. Each event is one file named
/// `<20-digit zero-padded sequence>-<event_id>.json`; sorting by filename gives FIFO order
/// for free and makes a torn write during a crash harmless — a write that never completed
/// its atomic rename simply never appears as a queued event (MOB-05).
///
/// Not an actor / not `Sendable`-checked: all access is serialized through a private
/// `DispatchQueue`, which is what makes "survives process kill mid-write" true — a write
/// either fully lands via `Data.write(options: .atomic)` (temp file + rename) or doesn't
/// exist at all; there is no partially-visible state.
public final class FileDiskQueue: DiskQueue {
    public struct Configuration {
        public var maxBytes: Int
        public var maxEventCount: Int

        public init(maxBytes: Int = 20 * 1024 * 1024, maxEventCount: Int = 5000) {
            self.maxBytes = maxBytes
            self.maxEventCount = maxEventCount
        }
    }

    private let directoryURL: URL
    private let configuration: Configuration
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accessQueue = DispatchQueue(label: "kit.apm.diskqueue")
    private var nextSequence: UInt64

    /// - Parameter directoryURL: a directory dedicated to this queue — nothing else should
    ///   write here, since eviction and recovery treat every `*.json` file as a queued event.
    public init(
        directoryURL: URL,
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default
    ) throws {
        self.directoryURL = directoryURL
        self.configuration = configuration
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        Self.applyDataProtection(to: directoryURL, fileManager: fileManager) // SEC-07
        self.nextSequence = try Self.recoverNextSequence(in: directoryURL, fileManager: fileManager)
    }

    public func enqueue(_ event: Event) throws {
        try accessQueue.sync {
            let sequence = nextSequence
            nextSequence += 1
            let url = fileURL(sequence: sequence, eventId: event.eventId)
            let data = try encoder.encode(event)
            try data.write(to: url, options: .atomic)
            try evictIfNeeded()
        }
    }

    public func peek(limit: Int) throws -> [Event] {
        try accessQueue.sync {
            try orderedFiles().prefix(limit).map { url in
                try decoder.decode(Event.self, from: try Data(contentsOf: url))
            }
        }
    }

    public func remove(eventIds: Set<String>) throws {
        guard !eventIds.isEmpty else { return }
        try accessQueue.sync {
            for url in try orderedFiles() where eventIds.contains(Self.eventId(from: url) ?? "") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public func count() throws -> Int {
        try accessQueue.sync { try orderedFiles().count }
    }

    public func sizeInBytes() throws -> Int {
        try accessQueue.sync { try orderedFiles().reduce(0) { $0 + (try fileSize($1)) } }
    }

    // MARK: - Eviction (MOB-06)

    private func evictIfNeeded() throws {
        var files = try orderedFiles()
        var totalSize = try files.reduce(0) { $0 + (try fileSize($1)) }

        while files.count > configuration.maxEventCount || totalSize > configuration.maxBytes {
            guard let oldest = files.first else { break }
            totalSize -= (try? fileSize(oldest)) ?? 0
            try? fileManager.removeItem(at: oldest)
            files.removeFirst()
        }
    }

    // MARK: - File naming / ordering

    private func orderedFiles() throws -> [URL] {
        try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func fileURL(sequence: UInt64, eventId: String) -> URL {
        directoryURL.appendingPathComponent("\(Self.pad(sequence))-\(eventId).json")
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int ?? 0
    }

    private static func pad(_ sequence: UInt64) -> String {
        String(format: "%020llu", sequence)
    }

    private static func eventId(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let separator = name.firstIndex(of: "-") else { return nil }
        return String(name[name.index(after: separator)...])
    }

    private static func recoverNextSequence(in directoryURL: URL, fileManager: FileManager) throws -> UInt64 {
        let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        let sequences: [UInt64] = contents.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            guard let separator = name.firstIndex(of: "-") else { return nil }
            return UInt64(name[name.startIndex..<separator])
        }
        return (sequences.max() ?? 0) + 1
    }

    /// SEC-07: queue directory uses `completeUntilFirstUserAuthentication` protection and is
    /// excluded from device backups. `FileProtectionType` is iOS-only; the macOS branch is
    /// test-scaffolding only (see `CONSTITUTION.md` platform invariants) — the SDK always
    /// ships on iOS, where this always applies.
    private static func applyDataProtection(to directoryURL: URL, fileManager: FileManager) {
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directoryURL.path
        )
        #endif
        var url = directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }
}
