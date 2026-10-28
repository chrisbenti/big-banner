import Foundation
import Network

/// Longest request (headers + body) the server will buffer.
private let maxRequestBytes = 64 * 1024

private let corsHeaders = [
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    // Chrome's Private Network Access preflight, for public sites calling localhost.
    "Access-Control-Allow-Private-Network": "true",
]

private struct HTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data
}

private enum ParseResult {
    case incomplete
    case complete(HTTPRequest)
    case malformed
}

/// Shows a banner for every HTTP request, one at a time. Each banner runs as a
/// child big-banner process, so the one-shot AppKit code stays untouched.
final class BannerServer {
    private let port: UInt16
    private let defaultArgs: [String]
    private let verbose: Bool
    private let queue = DispatchQueue(label: "big-banner.server")
    private var pending: [[String]] = []
    private var running: Process?

    init(port: UInt16, defaultArgs: [String], verbose: Bool) {
        self.port = port
        self.defaultArgs = defaultArgs
        self.verbose = verbose
    }

    private func log(_ msg: String) {
        guard verbose else { return }
        print("[big-banner] \(msg)")
        fflush(stdout)
    }

    func start() {
        let params = NWParameters.tcp
        // Loopback only: CORS allows any site, so the LAN must not be able to reach this.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            fail("could not listen on port \(port): \(error)")
        }
        listener.newConnectionHandler = { [self] conn in
            conn.start(queue: queue)
            receive(conn, buffer: Data())
        }
        listener.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                printStartupMessage()
            case .failed(let error):
                fail("could not listen on port \(port): \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    private func fail(_ msg: String) -> Never {
        FileHandle.standardError.write(Data("big-banner: \(msg)\n".utf8))
        exit(1)
    }

    private func printStartupMessage() {
        let url = "http://127.0.0.1:\(port)/"
        print("""
        big-banner listening on \(url)

        Call it from JavaScript (browser console, or a bookmarklet):

          // Async, blocking: waits until the server has accepted the banner
          const res = await fetch("\(url)?" + new URLSearchParams({ text: "Hello", super: "Heads up", sub: "from JS" }));
          console.log(await res.json());

          // Async, non-blocking: fires the request and carries on immediately
          fetch("\(url)?" + new URLSearchParams({ text: "Hello" })).catch(() => {});

        Press Ctrl-C to stop.
        """)
        fflush(stdout)
    }

    // MARK: - HTTP

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > maxRequestBytes {
                return respond(conn, status: 413, reason: "Payload Too Large", json: ["error": "request too large"])
            }
            switch parse(buf) {
            case .complete(let req):
                handle(req, on: conn)
            case .malformed:
                respond(conn, status: 400, reason: "Bad Request", json: ["error": "malformed request"])
            case .incomplete:
                if error != nil || isComplete {
                    conn.cancel()
                } else {
                    receive(conn, buffer: buf)
                }
            }
        }
    }

    private func parse(_ buf: Data) -> ParseResult {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: buf[..<sep.lowerBound], encoding: .utf8) else { return .malformed }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .malformed }
        let body = buf[sep.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            target: String(requestLine[1]),
            headers: headers,
            body: Data(body.prefix(length))
        ))
    }

    private func handle(_ req: HTTPRequest, on conn: NWConnection) {
        log("\(req.method) \(req.target)")
        if req.method == "OPTIONS" {
            return respond(conn, status: 204, reason: "No Content")
        }
        guard req.method == "GET" || req.method == "POST" else {
            return respond(conn, status: 405, reason: "Method Not Allowed", json: ["error": "use GET or POST"])
        }

        var params = queryParams(URLComponents(string: "http://localhost" + req.target)?.percentEncodedQueryItems)
        if req.method == "POST" {
            params.merge(bodyParams(req)) { _, body in body }
        }

        switch childArgs(from: params) {
        case .failure(let err):
            respond(conn, status: 400, reason: "Bad Request", json: ["error": err.message])
        case .success(let args):
            let position = enqueue(args)
            respond(conn, status: 202, reason: "Accepted", json: ["queued": position])
        }
    }

    private func queryParams(_ items: [URLQueryItem]?) -> [String: String] {
        var out: [String: String] = [:]
        // URLSearchParams and HTML forms encode spaces as "+", which URLComponents leaves alone.
        func decode(_ s: String?) -> String {
            (s ?? "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        for item in items ?? [] { out[decode(item.name)] = decode(item.value) }
        return out
    }

    private func bodyParams(_ req: HTTPRequest) -> [String: String] {
        let isJSON = (req.headers["content-type"] ?? "").contains("json")
        if isJSON {
            guard let obj = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any] else { return [:] }
            return obj.mapValues { "\($0)" }
        }
        var comps = URLComponents()
        comps.percentEncodedQuery = String(data: req.body, encoding: .utf8)
        return queryParams(comps.percentEncodedQueryItems)
    }

    // MARK: - Banner arguments

    private struct ParamError: Error { let message: String }

    private func isOff(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["0", "false", "no", "off"].contains(value.lowercased())
    }

    private func isOn(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on", ""].contains(value.lowercased())
    }

    private func childArgs(from params: [String: String]) -> Result<[String], ParamError> {
        let text = (params["text"] ?? params["msg"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(ParamError(message: "missing text")) }

        var args = defaultArgs
        if let name = params["theme"] {
            guard let theme = Themes.all.first(where: { $0.flag == "--" + name }) else {
                let known = Themes.all.map { String($0.flag.dropFirst(2)) }.joined(separator: ", ")
                return .failure(ParamError(message: "unknown theme '\(name)' (use one of: \(known))"))
            }
            args.append(theme.flag)
        }
        if isOff(params["bell"]) { args.append("--no-bell") }
        if isOff(params["sheet"]) { args.append("--no-sheet") }
        if isOn(params["pause"]) { args.append("--pause") }
        if let s = params["super"] { args += ["--super", s] }
        if let s = params["sub"] { args += ["--sub", s] }
        // "--" keeps request text from ever being read as a flag.
        args += ["--", text]
        return .success(args)
    }

    // MARK: - Banner queue

    /// Adds a banner to the queue and returns its position (1 = showing now).
    /// Always called on `queue`, as is everything that touches `pending`/`running`.
    private func enqueue(_ args: [String]) -> Int {
        let position = pending.count + (running == nil ? 0 : 1) + 1
        pending.append(args)
        startNextIfIdle()
        return position
    }

    private func startNextIfIdle() {
        guard running == nil, !pending.isEmpty else { return }
        let args = pending.removeFirst()
        let process = Process()
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = args
        process.terminationHandler = { [self] _ in
            queue.async {
                self.running = nil
                self.startNextIfIdle()
            }
        }
        do {
            log("showing banner: \(args.joined(separator: " "))")
            try process.run()
            running = process
        } catch {
            log("could not launch banner: \(error)")
            startNextIfIdle()
        }
    }

    // MARK: - Responses

    private func respond(_ conn: NWConnection, status: Int, reason: String, json: [String: Any]? = nil) {
        var headers = corsHeaders
        headers["Connection"] = "close"
        var body = Data()
        if let json, let data = try? JSONSerialization.data(withJSONObject: json) {
            body = data
            headers["Content-Type"] = "application/json"
        }
        headers["Content-Length"] = String(body.count)

        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        conn.send(
            content: Data(head.utf8) + body,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in conn.cancel() }
        )
    }
}

/// Starts the server and parks the main thread; never returns.
func runServer(port: UInt16, defaultArgs: [String], verbose: Bool) -> Never {
    BannerServer(port: port, defaultArgs: defaultArgs, verbose: verbose).start()
    dispatchMain()
}
