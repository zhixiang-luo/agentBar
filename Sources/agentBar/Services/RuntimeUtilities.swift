import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ShellRunner {
    static let standardSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.bun/bin",
        "\(NSHomeDirectory())/.cargo/bin",
        "/usr/bin",
        "/bin"
    ]

    static func findExecutable(named name: String) -> String? {
        let fm = FileManager.default
        for dir in standardSearchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":").map(String.init) {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    static func runShell(_ command: String, timeout: TimeInterval = 8.0) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]

                var env = ProcessInfo.processInfo.environment
                let existingPath = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = (standardSearchPaths + [existingPath]).joined(separator: ":")
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                let lock = NSLock()
                var finished = false

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    lock.lock()
                    let shouldKill = !finished
                    lock.unlock()
                    if shouldKill && process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    lock.lock()
                    finished = true
                    lock.unlock()
                    timer.cancel()

                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ShellResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr))
                } catch {
                    lock.lock()
                    finished = true
                    lock.unlock()
                    timer.cancel()
                    continuation.resume(returning: ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
    }
}

enum HTTPClient {
    static func makeSession(proxyURL: String, timeout: TimeInterval = 10.0) -> URLSession {
        // 使用 default 配置确保可靠继承 macOS 系统代理（如 Clash Verge 系统代理），同时禁用本地缓存
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout

        let effectiveProxy = resolveProxyURL(explicit: proxyURL)
        if !effectiveProxy.isEmpty,
           let url = URL(string: effectiveProxy),
           let host = url.host,
           let port = url.port {
            let scheme = (url.scheme ?? "http").lowercased()
            if scheme.hasPrefix("socks") {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: true,
                    kCFNetworkProxiesSOCKSProxy as String: host,
                    kCFNetworkProxiesSOCKSPort as String: port
                ]
            } else {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: true,
                    kCFNetworkProxiesHTTPProxy as String: host,
                    kCFNetworkProxiesHTTPPort as String: port,
                    kCFNetworkProxiesHTTPSEnable as String: true,
                    kCFNetworkProxiesHTTPSProxy as String: host,
                    kCFNetworkProxiesHTTPSPort as String: port
                ]
            }
        }

        return URLSession(configuration: config)
    }

    private static func resolveProxyURL(explicit: String) -> String {
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let env = ProcessInfo.processInfo.environment
        for key in ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"] {
            if let val = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                return val
            }
        }
        return ""
    }
}

enum JSONPathExtractor {
    /// 支持点路径和数组下标，例如 `balance_infos.0.total_balance` 或 `data.remaining`
    static func extractDouble(from jsonObject: Any, path: String) -> Double? {
        guard let value = extractValue(from: jsonObject, path: path) else { return nil }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let str = value as? String {
            return Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func extractString(from jsonObject: Any, path: String) -> String? {
        guard let value = extractValue(from: jsonObject, path: path) else { return nil }
        if let str = value as? String { return str }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func extractValue(from jsonObject: Any, path: String) -> Any? {
        let components = path
            .split(separator: ".")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var current: Any = jsonObject
        for key in components {
            if let dict = current as? [String: Any], let next = dict[key] {
                current = next
            } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }
}
