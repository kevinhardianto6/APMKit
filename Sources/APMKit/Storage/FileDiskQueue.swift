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
    private let selfHealth: SelfHealthCounters
    private let encryption: DiskQueueEncryption?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accessQueue = DispatchQueue(label: "kit.apm.diskqueue")
    private var nextSequence: UInt64

    /// - Parameter directoryURL: a directory dedicated to this queue — nothing else should
    ///   write here, since eviction and recovery treat every `*.json` file as a queued event.
    /// - Parameter selfHealth: eviction under the size/count cap (MOB-06) permanently drops an
    ///   event that was never sent — counted here (MOB-27, feat-010) since this is the one
    ///   place that decision happens.
    /// - Parameter encryption: SEC-08 (feat-014) at-rest encryption, real by default
    ///   (`AESGCMDiskQueueEncryption` over `KeychainDiskQueueKeyStore`) — every production
    ///   caller that doesn't override this gets encryption automatically, no composition root
    ///   required to opt in. Pass `nil` only when a test needs to inspect raw plaintext bytes
    ///   (e.g. the SEC-01/05/06 "no PII on disk" leak tests, which test the scrubbing layer
    ///   *before* encryption — testing post-encryption ciphertext there would trivially pass
    ///   regardless of a scrubbing bug and prove nothing).
    public init(
        directoryURL: URL,
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default,
        selfHealth: SelfHealthCounters = .shared,
        encryption: DiskQueueEncryption? = AESGCMDiskQueueEncryption(keyStore: KeychainDiskQueueKeyStore())
    ) throws {
        self.directoryURL = directoryURL
        self.configuration = configuration
        self.fileManager = fileManager
        self.selfHealth = selfHealth
        self.encryption = encryption
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        Self.applyDataProtection(to: directoryURL, fileManager: fileManager) // SEC-07
        self.nextSequence = try Self.recoverNextSequence(in: directoryURL, fileManager: fileManager)
    }

    public func enqueue(_ event: Event) throws {
        try accessQueue.sync {
            let sequence = nextSequence
            nextSequence += 1
            let url = fileURL(sequence: sequence, eventId: event.eventId)
            var data = try encoder.encode(event)
            if let encryption {
                data = try encryption.encrypt(data)
            }
            try data.write(to: url, options: .atomic)
            try evictIfNeeded()
        }
    }

    /// Skips (never throws for) a single file that fails to decrypt or decode, rather than
    /// aborting the whole batch — a "poison" file (a stale key after Keychain data loss, a
    /// pre-upgrade plaintext file from before this SDK version added encryption, ...) must
    /// never block every *other* already-encrypted event behind it from ever being read again
    /// (`CONSTITUTION.md` rule #1). Left on disk rather than deleted — MOB-06 eviction
    /// reclaims the space naturally under real pressure; deleting on a merely-ambiguous
    /// failure would be a needless destructive step.
    public func peek(limit: Int) throws -> [Event] {
        try accessQueue.sync {
            var events: [Event] = []
            for url in try orderedFiles() {
                guard events.count < limit else { break }
                guard let rawData = try? Data(contentsOf: url) else { continue }
                let decodable: Data
                if let encryption {
                    guard let decrypted = try? encryption.decrypt(rawData) else {
                        selfHealth.recordDropped()
                        continue
                    }
                    decodable = decrypted
                } else {
                    decodable = rawData
                }
                guard let event = try? decoder.decode(Event.self, from: decodable) else {
                    selfHealth.recordDropped()
                    continue
                }
                events.append(event)
            }
            return events
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
            selfHealth.recordDropped()
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
