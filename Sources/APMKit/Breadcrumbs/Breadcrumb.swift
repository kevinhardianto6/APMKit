import Foundation

/// docs/01 §4.5 `breadcrumb` categories.
public enum BreadcrumbCategory: String, Codable, Equatable {
    case navigation
    case userAction = "user_action"
    case network
    case lifecycle
    case state
    case log
}

/// docs/01 §4.5 `breadcrumb` levels.
public enum BreadcrumbLevel: String, Codable, Equatable {
    case debug, info, warning, error
}

/// One breadcrumb entry — docs/00 glossary: "catatan kronologis aksi kecil sebelum terjadi
/// error, seperti kotak hitam pesawat" (a chronological trail of small actions before an
/// error, like a flight recorder). Lives only in the in-memory `BreadcrumbRingBuffer`; never
/// queued as its own disk event (MOB-13: attached to crash/error events, not logged
/// standalone) — see `BreadcrumbRingBuffer`'s doc comment for the full reasoning.
public struct Breadcrumb: Codable, Equatable {
    public var category: BreadcrumbCategory
    public var message: String
    public var level: BreadcrumbLevel
    public var timestamp: String

    public init(
        category: BreadcrumbCategory,
        message: String,
        level: BreadcrumbLevel = .info,
        timestamp: Date = Date()
    ) {
        self.category = category
        self.message = message
        self.level = level
        self.timestamp = ISO8601Formatting.string(from: timestamp)
    }
}
