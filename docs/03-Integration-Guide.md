# APMKit Integration Guide

Target (MOB-25): a from-scratch integration into an existing iOS app, following only this
document, completes in under 30 minutes.

## Prerequisites

- An existing iOS app project (Xcode project or workspace), iOS 15+ deployment target.
- Your APM Kit ingest endpoint URL and app key (from your backend team).

## Step 1 — Add the package dependency

**Xcode UI:** File → Add Package Dependencies… → enter the APMKit repository URL → Add Package,
selecting the `APMKit` library product for your app target.

**Or, editing a Swift Package manifest directly**, add to `Package.swift`:

```swift
dependencies: [
    .package(url: "<APMKit repository URL>", from: "0.0.3")
],
targets: [
    .target(name: "YourApp", dependencies: ["APMKit"])
]
```

## Step 2 — Start the SDK at launch

In your `@main App` (SwiftUI) or `AppDelegate` (`application(_:didFinishLaunchingWithOptions:)`
for UIKit), call `APM.start(configuration:)` once, as early as possible:

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

This one call assembles and wires the entire pipeline: encrypted disk queue, scrubbing, the kill
switch, crash reporting, hang detection, an initial remote-config fetch, and background/
connectivity-triggered sync — nothing else is required for the SDK to be fully operational.

Keep `apm` (the returned `APMInstance`) around — the calls below use it.

## Step 3 — Capture your own network traffic (optional)

If you want automatic network observability, use `apm.instrumentedSession()` in place of
`URLSession(configuration:)` wherever your app builds its own session(s):

```swift
let (session, _) = apm.instrumentedSession()
// use `session` for your app's own API calls
```

Your APM Kit ingest traffic is automatically excluded from capture — no manual step needed.

## Step 4 — Report errors and set the user (optional, but read this one)

```swift
apm.logError(someError, context: ["screen": "checkout"])
APM.setUser(id: "user-123")            // raw value; hashing happens server-side
APM.breadcrumb("tapped_checkout", category: .userAction)
```

`APM.setUser` is the only step in this guide that's "optional" in a way worth pausing on. If
your app never calls it, every session still gets a `user_id` — the SDK generates and persists
a stable per-install fallback — so nothing looks broken. But that fallback can never be
correlated to a real user in User Lookup (`user_id_source` reports `generated`, not `host`),
and there's no error or warning to tell you this happened. If your team plans to search
sessions by phone number, email, or internal user id in the Backoffice, call `setUser` as soon
as you know who the user is (login, or app launch for an already-signed-in user) — not just
when convenient.

## Step 5 — Record cold-start (optional, but recommended)

Call once, from wherever your app considers "first frame drawn":

```swift
apm.recordFirstFrame()
```

## Done when

- The app builds and links against APMKit with no errors.
- `APM.start(configuration:)` is called once at launch with your real ingest endpoint.
- The app runs and no fatal errors occur.

Steps 3–5 are optional depending on which signals you want; the SDK is fully operational (queuing,
encrypting, syncing, crash/hang reporting, kill switch) after Step 2 alone.

## Advanced / custom pipelines

Every type `APM.start` assembles (`SessionManager`, `FileDiskQueue`, `IngestClient`,
`SyncEngine`, `RemoteConfigStore`, ...) is public and independently usable — `APM.start` is a
convenience layer, not the only way to use this SDK. See each type's own doc comments.

## Certificate pinning (optional, P2)

Pass `pinning:` in `Configuration` — a backup pin is mandatory (the initializer refuses to
construct without one):

```swift
let pinning = CertificatePinningConfiguration(
    primaryPin: primaryPinSHA256,
    backupPins: [backupPinSHA256]
)!
apm = APM.start(configuration: .init(ingestEndpoint: endpoint, pinning: pinning))
```

A pin is the SHA-256 hash of a certificate's raw DER bytes
(`CertificatePinningConfiguration.pin(forCertificateDER:)`). To disable pinning remotely without
an app release, your backend serves `disabled_features: ["cert_pinning"]` in `GET /v1/config` —
the connection falls back to the plain TLS floor (still fully verified), never to an unverified
one.
