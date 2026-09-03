import Testing
import Foundation
@testable import APMKit

@Suite("Envelope JSON shape — docs/01 §2")
struct EnvelopeTests {
    @Test("encodes the exact envelope field set with snake_case keys")
    func encodesExactShape() throws {
        let envelope = Envelope(
            sdk: SDKInfo(
                name: "apmkit-ios", version: "1.0.0",
                health: SDKHealth(written: 1420, sent: 1398, dropped: 22, dropReasons: ["queue_full": 18, "rejected": 4])
            ),
            app: AppInfo(id: "com.company.appname", version: "3.2.1", build: "1042"),
            device: DeviceInfo(
                os: "iOS", osVersion: "17.4", model: "iPhone14,2",
                locale: "id_ID", timezone: "Asia/Jakarta"
            ),
            integrity: IntegritySnapshot(
                isEmulator: false, isRooted: false, isDevMode: false, debuggerAttached: false
            ),
            installId: "8f14e45f-ea1a-4f2c-9d3b-7c2a1b0e5d44",
            sessionId: "b3d9c1a2-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
            userId: "client-supplied-string-or-sdk-generated",
            userIdSource: .host,
            events: []
        )

        let data = try JSONEncoder().encode(envelope)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["schema_version"] as? Int == 1)
        #expect(json["install_id"] as? String == "8f14e45f-ea1a-4f2c-9d3b-7c2a1b0e5d44")
        #expect(json["session_id"] as? String == "b3d9c1a2-5e6f-4a7b-8c9d-0e1f2a3b4c5d")
        #expect(json["user_id"] as? String == "client-supplied-string-or-sdk-generated")
        #expect(json["user_id_source"] as? String == "host")
        #expect(json["events"] as? [[String: Any]] != nil)

        let sdk = try #require(json["sdk"] as? [String: Any])
        #expect(sdk["name"] as? String == "apmkit-ios")
        #expect(sdk["version"] as? String == "1.0.0")
        let health = try #require(sdk["health"] as? [String: Any])
        #expect(health["written"] as? Int == 1420)
        #expect(health["sent"] as? Int == 1398)
        #expect(health["dropped"] as? Int == 22)
        let dropReasons = try #require(health["drop_reasons"] as? [String: Int])
        #expect(dropReasons == ["queue_full": 18, "rejected": 4])

        let app = try #require(json["app"] as? [String: Any])
        #expect(app["id"] as? String == "com.company.appname")
        #expect(app["version"] as? String == "3.2.1")
        #expect(app["build"] as? String == "1042")

        let device = try #require(json["device"] as? [String: Any])
        #expect(device["os"] as? String == "iOS")
        #expect(device["os_version"] as? String == "17.4")
        #expect(device["model"] as? String == "iPhone14,2")
        #expect(device["locale"] as? String == "id_ID")
        #expect(device["timezone"] as? String == "Asia/Jakarta")

        let integrity = try #require(json["integrity"] as? [String: Any])
        #expect(integrity["is_emulator"] as? Bool == false)
        #expect(integrity["is_rooted"] as? Bool == false)
        #expect(integrity["is_dev_mode"] as? Bool == false)
        #expect(integrity["debugger_attached"] as? Bool == false)

        // No extra top-level fields beyond the schema.
        #expect(Set(json.keys) == [
            "schema_version", "sdk", "app", "device", "integrity",
            "install_id", "session_id", "user_id", "user_id_source", "events"
        ])
    }

    @Test("user_id encodes as null when unset, not omitted")
    func nilUserIdRoundTrips() throws {
        let envelope = Envelope(
            app: AppInfo(id: "com.company.appname", version: "1.0", build: "1"),
            device: DeviceInfo(os: "iOS", osVersion: "17.4", model: "x", locale: "en_US", timezone: "UTC"),
            installId: UUID().uuidString,
            sessionId: UUID().uuidString,
            userId: nil,
            events: []
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        #expect(decoded.userId == nil)
        #expect(decoded.userIdSource == nil)
    }

    @Test("round-trips through encode/decode unchanged")
    func roundTrips() throws {
        let original = Envelope(
            app: AppInfo(id: "com.company.appname", version: "1.0", build: "1"),
            device: DeviceInfo(os: "iOS", osVersion: "17.4", model: "x", locale: "en_US", timezone: "UTC"),
            installId: UUID().uuidString,
            sessionId: UUID().uuidString,
            userId: "some-user",
            events: [Event(type: "network", seq: 1)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        #expect(decoded == original)
    }

    @Test("rejecting an unknown schema_version is the backend's job, not the SDK's")
    func schemaVersionDefaultsToCurrent() {
        let envelope = Envelope(
            app: AppInfo(id: "x", version: "1", build: "1"),
            device: DeviceInfo(os: "iOS", osVersion: "1", model: "x", locale: "en_US", timezone: "UTC"),
            installId: "i", sessionId: "s", userId: nil, events: []
        )
        #expect(envelope.schemaVersion == Envelope.currentSchemaVersion)
    }
}
