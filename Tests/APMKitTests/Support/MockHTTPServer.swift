import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A minimal loopback-only HTTP/1.1 server for driving *real* `URLSession` requests in
/// tests, without a third-party dependency (raw BSD sockets — same "Foundation/Network only"
/// budget the shipped SDK has, just used here for test infrastructure instead of production
/// code). Good enough to exercise the real `URLSessionTaskDelegate` capture path; not a
/// general-purpose HTTP server (no persistent connections, no chunked bodies, no pipelining).
final class MockHTTPServer {
    enum Behavior {
        case respond(status: Int, headers: [String: String] = [:], body: Data = Data())
        /// Accepts the connection but never writes a response — the client-side request
        /// will time out. Used to produce a *real* `NSURLErrorTimedOut`.
        case hang
    }

    private(set) var port: UInt16 = 0
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "mock-http-server.accept")
    private let connectionQueue = DispatchQueue(label: "mock-http-server.connections", attributes: .concurrent)
    private var isRunning = false
    private var handler: (_ method: String, _ path: String) -> Behavior

    init(handler: @escaping (String, String) -> Behavior = { _, _ in .respond(status: 200) }) {
        self.handler = handler
    }

    func start() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.EIO) }

        var reuse: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // ask the OS for an ephemeral port

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listenFD, $0, &len)
            }
        }
        port = UInt16(bigEndian: boundAddr.sin_port)

        guard listen(listenFD, 32) == 0 else { throw POSIXError(.EIO) }
        isRunning = true

        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        isRunning = false
        if listenFD >= 0 { close(listenFD) }
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { continue }
            connectionQueue.async { [weak self] in self?.handle(clientFD: clientFD) }
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(clientFD, &buffer, buffer.count)
        guard n > 0, let request = String(bytes: buffer[0..<n], encoding: .utf8) else { return }

        let requestLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        switch handler(method, path) {
        case .respond(let status, let headers, let body):
            writeResponse(clientFD: clientFD, status: status, headers: headers, body: body)
        case .hang:
            // Hold the connection open without responding. The test's URLSessionConfiguration
            // uses a short timeoutIntervalForRequest, so the client sees a real timeout.
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private func writeResponse(clientFD: Int32, status: Int, headers: [String: String], body: Data) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        allHeaders["Connection"] = "close"
        for (key, value) in allHeaders { head += "\(key): \(value)\r\n" }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        data.withUnsafeBytes { raw in
            _ = raw.baseAddress.map { write(clientFD, $0, raw.count) }
        }
    }
}
