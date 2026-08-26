import Foundation
@testable import APMKit

/// Thread-safe `EventSink` fake for assertions in tests. `NetworkCaptureDelegate` calls
/// `receive` from URLSession's delegate queue, which is a different thread than the test.
final class CollectingEventSink: EventSink {
    private let lock = NSLock()
    private var _events: [Event] = []

    var events: [Event] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func receive(_ event: Event) {
        lock.lock()
        _events.append(event)
        lock.unlock()
    }
}

/// Polls `sink.events` until at least `count` have arrived or `timeout` elapses — delegate
/// callbacks land asynchronously on URLSession's delegate queue, slightly after an `async`
/// request call returns.
func waitForEvents(_ sink: CollectingEventSink, count: Int, timeout: TimeInterval = 3) async -> [Event] {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if sink.events.count >= count { return sink.events }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return sink.events
}
