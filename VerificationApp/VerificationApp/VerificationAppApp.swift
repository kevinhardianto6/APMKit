import SwiftUI
import APMKit

@main
struct VerificationAppApp: App {
    let apm: APMInstance

    init() {
        // Checklist item 5 (docs/02 §5): APM.start's own synchronous cold-start overhead,
        // measured for real on the launch path — previously impossible without a real app.
        let start = CFAbsoluteTimeGetCurrent()
        apm = APM.start(configuration: .init(
            ingestEndpoint: IngestEndpoint(
                url: URL(string: "https://ingest.yourcompany.com/v1/ingest")!,
                appKey: "your-app-key"
            )
        ))
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        NSLog("APMKIT_COLDSTART_MS=%.3f", elapsedMs)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(apm: apm)
        }
    }
}
