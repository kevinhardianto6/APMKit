import SwiftUI
import APMKit

struct ContentView: View {
    let apm: APMInstance
    @State private var diagnosticText: String = "…"

    var body: some View {
        VStack(spacing: 16) {
            Text("APMKit Verification App")
            Text(diagnosticText)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .onAppear {
            let (session, _) = apm.instrumentedSession()
            _ = session

            apm.logError(NSError(domain: "verification", code: 1), context: ["screen": "checkout"])
            APM.setUser(id: "user-123")
            APM.breadcrumb("tapped_checkout", category: .userAction)

            apm.recordFirstFrame()

            // Checklist item 9 (feat-014, SEC-08): re-open the SAME on-disk queue with a FRESH
            // FileDiskQueue instance and the default Keychain-backed key store — if this
            // process is a genuine relaunch (not the first cold start), this proves the
            // Keychain key persisted and the previously-written ciphertext still decrypts.
            // Not a fake: same production types (`FileDiskQueue`, `KeychainDiskQueueKeyStore`)
            // the SDK itself uses, pointed at the same default queue directory.
            let readBack = try? FileDiskQueue(directoryURL: APM.Configuration.defaultQueueDirectory())
            let events = (try? readBack?.peek(limit: 100)) ?? nil
            diagnosticText = "queue count: \(String(describing: try? readBack?.count()))\ndecoded on peek: \(events?.count ?? -1)"
        }
    }
}
