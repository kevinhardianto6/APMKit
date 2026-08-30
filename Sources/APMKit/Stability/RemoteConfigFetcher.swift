import Foundation

/// Real `GET /v1/config` implementation (docs/01 §9). Same anti-loop discipline as
/// `IngestClient` (feat-005, MOB-09): the caller-provided `URLSession` must never be
/// `APM.instrumentedSession()`, and the default `init` constructs a bare session with no
/// custom delegate — this is the SDK's own traffic, not something to capture.
public final class RemoteConfigFetcher {
    private let endpoint: IngestEndpoint
    let session: URLSession
    private let decoder = JSONDecoder()

    public init(endpoint: IngestEndpoint, session: URLSession = URLSession(configuration: .default)) {
        self.endpoint = endpoint
        self.session = session
    }

    /// `nil` on any failure (network error, non-200, malformed body) — the caller
    /// (`RemoteConfigStore`) is what decides the fallback (cache, then `.safeDefault`);
    /// this type only knows how to talk to the endpoint.
    public func fetch(completion: @escaping (RemoteConfig?) -> Void) {
        var request = URLRequest(url: endpoint.configURL)
        request.httpMethod = "GET"
        request.setValue(endpoint.appKey, forHTTPHeaderField: "X-APM-Key")
        request.setValue("\(SDKInfo.current.name)/\(SDKInfo.current.version)", forHTTPHeaderField: "X-APM-Sdk")

        session.dataTask(with: request) { [decoder] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let config = try? decoder.decode(RemoteConfig.self, from: data)
            else {
                completion(nil)
                return
            }
            completion(config)
        }.resume()
    }
}
