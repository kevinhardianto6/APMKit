import Foundation

/// Abstracts the actual `POST /v1/ingest` call so `SyncEngine`'s response-contract logic
/// (docs/01 §7) is testable without real networking — tests supply a fake that returns a
/// scripted `UploadOutcome`; `IngestClient` is the real implementation.
public protocol IngestUploading {
    func upload(envelope: Envelope, completion: @escaping (UploadOutcome) -> Void)
}
