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
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

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
    private var handler: (Request) -> Behavior

    /// `simpleHandler`, if provided, only looks at method/path — kept for call sites that
    /// don't care about headers/body (most of feat-003's tests).
    convenience init(handler simpleHandler: @escaping (String, String) -> Behavior) {
        self.init { request in simpleHandler(request.method, request.path) }
    }

    init(handler: @escaping (Request) -> Behavior = { _ in .respond(status: 200) }) {
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
        guard let request = readRequest(clientFD: clientFD) else { return }

        switch handler(request) {
        case .respond(let status, let headers, let body):
            writeResponse(clientFD: clientFD, status: status, headers: headers, body: body)
        case .hang:
            // Hold the connection open without responding. The test's URLSessionConfiguration
            // uses a short timeoutIntervalForRequest, so the client sees a real timeout.
            Thread.sleep(forTimeInterval: 5)
        }
    }

    /// Reads until the header terminator is seen, then keeps reading until `Content-Length`
    /// worth of body has arrived — a single `read()` isn't guaranteed to return the whole
    /// request in one call, especially for gzip-compressed bodies larger than one TCP segment.
    private func readRequest(clientFD: Int32) -> Request? {
        var buffer = Data()
        var headerEnd: Range<Data.Index>?
        let terminator = Data("\r\n\r\n".utf8)

        while headerEnd == nil {
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = read(clientFD, &chunk, chunk.count)
            guard n > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            headerEnd = buffer.range(of: terminator)
        }

        guard let headerEnd, let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestLineParts = (lines.first ?? "").split(separator: " ")
        let method = requestLineParts.count > 0 ? String(requestLineParts[0]) : "GET"
        let path = requestLineParts.count > 1 ? String(requestLineParts[1]) : "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0
        var body = buffer[headerEnd.upperBound...]
        while body.count < contentLength {
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = read(clientFD, &chunk, chunk.count)
            guard n > 0 else { break }
            body.append(contentsOf: chunk[0..<n])
        }

        return Request(method: method, path: path, headers: headers, body: Data(body))
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
