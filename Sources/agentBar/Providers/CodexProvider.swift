import Foundation

struct CodexProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[1]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let fm = FileManager.default
        let codexDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let authURL = codexDir.appendingPathComponent("auth.json")
        let sessionsDir = codexDir.appendingPathComponent("sessions")
        let installed = fm.fileExists(atPath: codexDir.path) || ShellRunner.findExecutable(named: "codex") != nil

        // 1. 优先读取 ~/.codex/auth.json 实时请求 Codex 额度接口（与最新真实额度完全同步）
        var liveErrorNote: String?
        if let auth = Self.loadLocalAuth(from: authURL) {
            do {
                let parsed = try await fetchLiveWhamUsage(auth: auth, proxyURL: context.config.proxyURL)
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: parsed.planType ?? "订阅额度",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .active,
                    windows: parsed.windows,
                    sourceLabel: "官方登录态实时同步",
                    updatedAt: now,
                    isInstalled: true
                )
            } catch {
                liveErrorNote = error.localizedDescription
            }
        }

        // 2. 离线/网络异常时，极速降级读取 ~/.codex/sessions/**/*.jsonl 最新 rate_limits 事件
        if let parsed = Self.scanLatestRateLimits(in: sessionsDir, now: now) {
            let source = liveErrorNote == nil ? "本机会话日志读取" : "离线日志降级（\(liveErrorNote!)）"
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: parsed.planType ?? "订阅额度",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .active,
                windows: parsed.windows,
                sourceLabel: source,
                updatedAt: parsed.timestamp ?? now,
                isInstalled: true
            )
        }

        // 3. 兼容读取标准本地缓存
        if let payload = context.store.readStandardCache(for: descriptor.id) {
            let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
            if !windows.isEmpty {
                let updatedAt = payload.updatedAt.map { Date(timeIntervalSince1970: $0) } ?? now
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: payload.subtitle ?? "订阅额度",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .active,
                    windows: windows,
                    sourceLabel: "本地缓存读取",
                    updatedAt: updatedAt,
                    isInstalled: true
                )
            }
        }

        if let liveErrorNote {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "同步失败",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .error(message: "Codex 实时同步失败：\(liveErrorNote)。若开启了代理，请在「设置 → 密钥与代理」检查代理地址。"),
                windows: [],
                sourceLabel: "实时同步",
                updatedAt: now,
                isInstalled: true
            )
        }

        if !installed {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "未安装",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .unavailable(reason: "未检测到本机 Codex"),
                windows: [],
                sourceLabel: "本地检测",
                updatedAt: now,
                isInstalled: false
            )
        }

        return AgentQuotaSnapshot(
            id: descriptor.id,
            name: descriptor.name,
            badge: "等待数据",
            accentHex: descriptor.accentHex,
            symbolName: descriptor.symbolName,
            status: .needsSetup(
                hint: "已检测到 ~/.codex 目录，请先登录 Codex 或发起一次对话以同步 5 小时与周额度。",
                action: nil
            ),
            windows: [],
            sourceLabel: "等待登录态",
            updatedAt: now,
            isInstalled: true
        )
    }

    // MARK: - 实时接口读取（~/.codex/auth.json -> chatgpt.com/backend-api/wham/usage）

    struct LocalCodexAuth {
        let accessToken: String
        let accountID: String?
    }

    static func loadLocalAuth(from url: URL) -> LocalCodexAuth? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let accountID = tokens["account_id"] as? String
        return LocalCodexAuth(accessToken: accessToken, accountID: accountID)
    }

    private func fetchLiveWhamUsage(auth: LocalCodexAuth, proxyURL: String) async throws -> ParsedCodexLimits {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let session = HTTPClient.makeSession(proxyURL: proxyURL, timeout: 10.0)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw NSError(domain: "CodexProvider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "登录态已过期，请重新打开 Codex 刷新登录"])
            }
            throw NSError(domain: "CodexProvider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }

        guard let parsed = Self.parseWhamUsageJSON(data: data) else {
            throw NSError(domain: "CodexProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "未解析到额度窗口"])
        }
        return parsed
    }

    static func parseWhamUsageJSON(data: Data) -> ParsedCodexLimits? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = obj["rate_limit"] as? [String: Any] else {
            return nil
        }

        var windows: [QuotaWindow] = []
        if let primary = rateLimit["primary_window"] as? [String: Any],
           let win = parseWindow(dict: primary, defaultLabel: "5 小时额度", id: "codex-primary") {
            windows.append(win)
        }
        if let secondary = rateLimit["secondary_window"] as? [String: Any],
           let win = parseWindow(dict: secondary, defaultLabel: "周额度", id: "codex-secondary") {
            windows.append(win)
        }

        // 若高级会员没有 5 小时限额，补充解析总/附加额度窗口或 Credits 余额
        if let additional = obj["additional_rate_limits"] as? [[String: Any]] {
            for (idx, item) in additional.enumerated() {
                if let sub = (item["rate_limit"] as? [String: Any]) ?? item as [String: Any]?,
                   let w = (sub["primary_window"] as? [String: Any]) ?? (sub["secondary_window"] as? [String: Any]) ?? sub as [String: Any]?,
                   let win = parseWindow(dict: w, defaultLabel: "全部额度", id: "codex-extra-\(idx)") {
                    windows.append(win)
                }
            }
        }
        if let credits = obj["credits"] as? [String: Any] {
            if let unlimited = credits["unlimited"] as? Bool, unlimited {
                windows.append(
                    QuotaWindow(
                        id: "codex-credits-unlimited",
                        label: "全部额度",
                        kind: .percentage(usedPercent: 0),
                        resetsAt: nil,
                        detail: "无限额度权益"
                    )
                )
            } else if let hasCredits = credits["has_credits"] as? Bool, hasCredits,
                      let bal = extractNumber(credits["balance"]), bal > 0 {
                windows.append(
                    QuotaWindow(
                        id: "codex-credits-balance",
                        label: "全部额度余额",
                        kind: .balance(amount: bal, currency: "USD", referenceCap: max(bal, 20.0)),
                        resetsAt: nil
                    )
                )
            }
        }

        guard !windows.isEmpty else { return nil }
        let planLabel = mapPlanType(obj["plan_type"] as? String)
        return ParsedCodexLimits(windows: windows, planType: planLabel, timestamp: Date())
    }

    // MARK: - 本地 JSONL 极速尾段扫描（离线兜底）

    struct ParsedCodexLimits {
        let windows: [QuotaWindow]
        let planType: String?
        let timestamp: Date?
    }

    static func scanLatestRateLimits(in sessionsDir: URL, now: Date = Date()) -> ParsedCodexLimits? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var jsonlFiles: [(url: URL, modified: Date)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            jsonlFiles.append((fileURL, values?.contentModificationDate ?? .distantPast))
        }

        jsonlFiles.sort { $0.modified > $1.modified }

        for entry in jsonlFiles.prefix(20) {
            if let content = readTailUTF8(from: entry.url, maxBytes: 512 * 1024),
               let parsed = parseRateLimits(fromJSONL: content, fallbackDate: entry.modified, now: now) {
                return parsed
            }
        }
        return nil
    }

    private static func readTailUTF8(from url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func parseRateLimits(fromJSONL content: String, fallbackDate: Date? = nil, now: Date = Date()) -> ParsedCodexLimits? {
        let lines = content.split(whereSeparator: \.isNewline).reversed()
        for lineSub in lines {
            let line = String(lineSub)
            guard line.contains("rate_limits") else { continue }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let payload = (obj["payload"] as? [String: Any]) ?? obj
            guard let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }

            var windows: [QuotaWindow] = []
            if let primary = (rateLimits["primary"] as? [String: Any]) ?? (rateLimits["primary_window"] as? [String: Any]),
               let win = parseWindow(dict: primary, defaultLabel: "5 小时额度", id: "codex-primary", now: now) {
                windows.append(win)
            }
            if let secondary = (rateLimits["secondary"] as? [String: Any]) ?? (rateLimits["secondary_window"] as? [String: Any]),
               let win = parseWindow(dict: secondary, defaultLabel: "周额度", id: "codex-secondary", now: now) {
                windows.append(win)
            }

            if !windows.isEmpty {
                let rawPlan = rateLimits["plan_type"] as? String
                let planLabel = mapPlanType(rawPlan)
                let tsString = obj["timestamp"] as? String
                let ts = StandardQuotaPayload.WindowItem.parseDate(epoch: nil, iso: tsString) ?? fallbackDate
                return ParsedCodexLimits(windows: windows, planType: planLabel, timestamp: ts)
            }
        }
        return nil
    }

    private static func parseWindow(
        dict: [String: Any],
        defaultLabel: String,
        id: String,
        now: Date? = nil
    ) -> QuotaWindow? {
        guard var used = extractNumber(dict["used_percent"]) ?? extractNumber(dict["used_percentage"]) else {
            return nil
        }

        let minutes = extractNumber(dict["window_minutes"])
            ?? extractNumber(dict["limit_window_seconds"]).map { $0 / 60.0 }
        let label = formatWindowLabel(minutes: minutes, fallback: defaultLabel)

        let resetEpoch = extractNumber(dict["resets_at"]) ?? extractNumber(dict["reset_at"])
        let resetISO = (dict["resets_at"] as? String) ?? (dict["reset_at"] as? String)
        var resetDate = StandardQuotaPayload.WindowItem.parseDate(epoch: resetEpoch, iso: resetISO)
        var detail: String? = nil

        // 如果是离线日志且该窗口的重置时间已过，说明该周期已经刷新清零
        if let now, let rDate = resetDate, rDate < now {
            used = 0
            resetDate = nil
            detail = "上周期已重置（等待新会话刷新）"
        }

        return QuotaWindow(
            id: id,
            label: label,
            kind: .percentage(usedPercent: used),
            resetsAt: resetDate,
            detail: detail
        )
    }

    private static func formatWindowLabel(minutes: Double?, fallback: String) -> String {
        guard let minutes else { return fallback }
        if abs(minutes - 300) <= 30 {
            return "5 小时额度"
        } else if abs(minutes - 10080) <= 120 {
            return "周额度"
        } else if minutes >= 25 * 1440 {
            return "月度额度"
        } else if minutes >= 1440 {
            let days = Int(round(minutes / 1440.0))
            return "\(days) 天额度"
        } else if minutes >= 60 {
            let hours = Int(round(minutes / 60.0))
            return "\(hours) 小时额度"
        }
        return fallback
    }

    private static func mapPlanType(_ plan: String?) -> String? {
        guard let plan = plan?.lowercased() else { return nil }
        switch plan {
        case "plus": return "Plus 订阅"
        case "pro": return "Pro 订阅"
        case "team": return "团队版"
        case "enterprise": return "企业版"
        default: return nil
        }
    }

    private static func extractNumber(_ value: Any?) -> Double? {
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String { return Double(str) }
        return nil
    }
}
