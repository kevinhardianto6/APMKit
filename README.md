# APMKit

In-house iOS Application Performance Monitoring SDK — crash reporting and network
observability, write-local-first (every event hits disk before any network call).

## Features

- **Network observability** — drop-in `URLSession` capture (latency, status, failure category),
  with automatic exclusion of the SDK's own upload traffic.
- **Crash reporting** — wraps [KSCrash](https://github.com/kstenerud/KSCrash); captures crashes
  and reports them on the next launch.
- **Termination reporting** — an OS-level kill your app could never catch live (memory
  pressure, thermal, CPU, low battery) is reported as its own `termination` event, distinct
  from `crash`. Ordinary terminations (Xcode Stop, a user swipe, a rebuild) are not reported at
  all — the OS gives no signal to distinguish them from each other, so counting them would only
  make crash-free rate falsely bad.
- **Main-thread hang detection** — live detection of >2s main-thread blocks.
- **Breadcrumbs** — automatic (app lifecycle, connectivity) and manual, attached to every crash
  and manual error report.
- **Manual error reporting** (`logError`) — auto-captures the call site (file/function/line),
  no extra arguments needed — and cold-start timing (`recordFirstFrame`).
- **Remote kill switch** — disable the SDK app-wide via remote config, no app release needed.
- **At-rest encryption** — the on-disk event queue is AES-GCM encrypted, key in Keychain.
- **Optional certificate pinning** — off by default; opt in per app with a mandatory backup pin
  and remote kill switch.
- **PII scrubbing** — headers (allowlist), query parameters, and path segments are scrubbed
  before anything reaches disk. Request/response bodies are never captured.

## Requirements

- iOS 15.0+
- Swift 5.9+ / Xcode 15+

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…**, enter the repository URL, and select the
`APMKit` library product.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kevinhardianto6/APMKit.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["APMKit"])
]
```

### CocoaPods

```ruby
pod 'APMKit', '~> 1.0'
```

## Quick start

One call, as early as possible during app launch, wires the entire pipeline — encrypted disk
queue, PII scrubbing, the remote kill switch, crash reporting, hang detection, an initial
remote-config fetch, and background/connectivity-triggered sync:

**SwiftUI:**

```swift
import APMKit

@main
struct YourApp: App {
    let apm: APMInstance

    init() {
        apm = APM.start(configuration: .init(
            ingestEndpoint: IngestEndpoint(
                url: URL(string: "https://ingest.yourcompany.com/v1/ingest")!,
                appKey: "your-app-key"
            )
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**UIKit (`AppDelegate`):** the call itself is identical — only where you hold the returned
`APMInstance` differs, since there's no SwiftUI `App` struct to store it on. Keep it as a
property on your `AppDelegate` (or a shared singleton, if other places in your codebase need
it too):

```swift
import UIKit
import APMKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var apm: APMInstance!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        apm = APM.start(configuration: .init(
            ingestEndpoint: IngestEndpoint(
                url: URL(string: "https://ingest.yourcompany.com/v1/ingest")!,
                appKey: "your-app-key"
            )
        ))
        return true
    }
}
```

If your project uses a separate `SceneDelegate` (the default multi-scene UIKit template),
`AppDelegate` is still the right place for this call — `application(_:didFinishLaunchingWithOptions:)`
runs once per process, before any `SceneDelegate` is created, which is exactly "as early as
possible during app launch." Reach `apm` from elsewhere via
`(UIApplication.shared.delegate as! AppDelegate).apm`, or thread it through your own dependency
injection if you have one — `SceneDelegate`'s `scene(_:willConnectTo:options:)` fires after this
and never needs its own `APM.start` call.

That's it — the SDK is fully operational. Everything else is optional:

```swift
// Automatic network observability for your own API calls:
let (session, _) = apm.instrumentedSession()

// Manual error reporting — file/function/line are captured automatically from this call site:
apm.logError(someError, context: ["screen": "checkout"])

// Identify the current user (sent raw; hashing happens server-side):
APM.setUser(id: "user-123")

// Manual breadcrumb:
APM.breadcrumb("tapped_checkout", category: .userAction)

// Cold-start timing — call once, wherever your app considers "first frame drawn":
apm.recordFirstFrame()
```

Every type `APM.start` assembles (`SessionManager`, `FileDiskQueue`, `IngestClient`,
`SyncEngine`, `RemoteConfigStore`, …) is public and independently usable for advanced/custom
pipelines — `APM.start` is a convenience layer, not the only way to use this SDK.

**Full walkthrough, including optional certificate pinning:**
[docs/03-Integration-Guide.md](docs/03-Integration-Guide.md).

## Documentation

| Doc | Contents |
|---|---|
| [docs/03-Integration-Guide.md](docs/03-Integration-Guide.md) | Step-by-step integration, including certificate pinning |
| [docs/00-Overview.md](docs/00-Overview.md) | Product overview and architecture |
| [docs/01-Kontrak-Data-API.md](docs/01-Kontrak-Data-API.md) | Wire format / backend API contract |
| [docs/02-Mobile-SDK.md](docs/02-Mobile-SDK.md) | Full SDK requirements spec |
| [CONSTITUTION.md](CONSTITUTION.md) | Architecture invariants, security rules, decisions |
| [VERSIONING.md](VERSIONING.md) | Semver policy and distribution details |
| [FEATURES.md](FEATURES.md) | What's shipped, what's in progress |

## Architecture

Every event follows a fixed pipeline, never reversed: **Capture → Scrub → Disk → Sync.** An
event is durably written to disk before any network call is attempted, and is only deleted
after a 2xx response from the ingest endpoint — this is what makes delivery at-least-once even
across a mid-upload process kill.

## Privacy & security notes

- Request/response bodies are never captured.
- Headers are filtered through an allowlist (`Content-Type`, `Content-Length`, `Accept`,
  `User-Agent`) — `Authorization`/`Cookie`/custom headers are never recorded.
- `logError`'s auto-captured `source_file` uses Swift's `#fileID` (`Module/File.swift`), never
  `#file` (an absolute build-machine path) — the latter would leak the developer's username and
  local directory layout into the monitoring backend on every error event.
- TLS 1.2+ is enforced on the SDK's own upload connection, independent of your app's ATS
  settings; any TLS validation failure fails closed (data stays queued, never sent over an
  unprotected connection).
- Embedding this SDK has store-listing consequences: apps must update their App Store Connect
  privacy label / Play Console Data Safety form to reflect the data this SDK collects.

## License

Proprietary — internal use only, not for public distribution.
