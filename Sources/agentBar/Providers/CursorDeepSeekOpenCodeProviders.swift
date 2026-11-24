import Foundation

// MARK: - Cursor

struct CursorProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[3]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let fm = FileManager.default
        let cursorSupport = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor")
        let cursorDot = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
        let apiKey = resolveAPIKey(from: context.config)
        let installed = fm.fileExists(atPath: cursorSupport.path)
            || fm.fileExists(atPath: cursorDot.path)
            || !apiKey.isEmpty

        // 1. 本地缓存优先
        if let payload = context.store.readStandardCache(for: descriptor.id) {
            let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
            if !windows.isEmpty {
                let updatedAt = payload.updatedAt.map { Date(timeIntervalSince1970: $0) } ?? now
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: payload.subtitle ?? "月度额度",
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

        // 2. 官方 Admin Spend API（配置密钥时可用）
        if !apiKey.isEmpty {
            do {
                let windows = try await fetchCursorSpend(apiKey: apiKey, config: context.config)
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: "月度账期",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .active,
                    windows: windows,
                    sourceLabel: "官方接口同步",
                    updatedAt: now,
                    isInstalled: true
                )
            } catch {
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: "同步异常",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .error(message: "Cursor 接口请求失败：\(error.localizedDescription)"),
                    windows: [],
                    sourceLabel: "官方接口",
                    updatedAt: now,
                    isInstalled: true
                )
            }
        }

        if !installed {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "未安装",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .unavailable(reason: "未检测到 Cursor"),
                windows: [],
                sourceLabel: "本地检测",
                updatedAt: now,
                isInstalled: false
            )
        }

        return AgentQuotaSnapshot(
            id: descriptor.id,
            name: descriptor.name,
            badge: "需配置密钥",
            accentHex: descriptor.accentHex,
            symbolName: descriptor.symbolName,
            status: .needsSetup(
                hint: "检测到本机已安装 Cursor，请在「设置 → 密钥与代理」填入 Cursor API Key。",
                action: .openSettings(.credentials)
            ),
            windows: [],
            sourceLabel: "等待配置",
            updatedAt: now,
            isInstalled: true
        )
    }

    private func resolveAPIKey(from config: AppConfig) -> String {
        let local = config.cursorAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return ProcessInfo.processInfo.environment["CURSOR_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func fetchCursorSpend(apiKey: String, config: AppConfig) async throws -> [QuotaWindow] {
        guard let url = URL(string: "https://api.cursor.com/teams/spend") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let basicToken = Data("\(apiKey):".utf8).base64EncodedString()
        req.setValue("Basic \(basicToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)

        let session = HTTPClient.makeSession(proxyURL: config.proxyURL)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "CursorProvider", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP 状态码 \(code)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CursorProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "返回数据格式无效"])
        }

        var spendCents = 0.0
        if let members = json["teamMemberSpend"] as? [[String: Any]] {
            for member in members {
                if let cents = (member["spendCents"] as? NSNumber)?.doubleValue {
                    spendCents += cents
                }
            }
        } else if let total = (json["overallSpendCents"] as? NSNumber)?.doubleValue {
            spendCents = total
        }

        let spentUSD = spendCents / 100.0
        let budget = max(config.cursorMonthlyBudgetUSD, 1.0)
        let usedPct = min(max((spentUSD / budget) * 100.0, 0), 100)

        let nextMonthStart: Date? = {
            let cal = Calendar.current
            let now = Date()
            guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return nil }
            return cal.date(byAdding: .month, value: 1, to: startOfMonth)
        }()

        return [
            QuotaWindow(
                id: "cursor-monthly",
                label: "本月预算额度",
                kind: .percentage(usedPercent: usedPct),
                resetsAt: nextMonthStart,
                detail: String(format: "已消费 $%.2f / $%.0f", spentUSD, budget)
            )
        ]
    }
}

// MARK: - DeepSeek

struct DeepSeekProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[4]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let apiKey = resolveAPIKey(from: context.config)

        guard !apiKey.isEmpty else {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "未配置密钥",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .unavailable(reason: "未配置 DeepSeek API Key"),
                windows: [],
                sourceLabel: "官方余额接口",
                updatedAt: now,
                isInstalled: false
            )
        }

        do {
            let windows = try await fetchBalance(apiKey: apiKey, config: context.config)
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "API 余额",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .active,
                windows: windows,
                sourceLabel: "官方接口实时查询",
                updatedAt: now,
                isInstalled: true
            )
        } catch {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "查询失败",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .error(message: "DeepSeek 余额查询失败：\(error.localizedDescription)"),
                windows: [],
                sourceLabel: "官方余额接口",
                updatedAt: now,
                isInstalled: true
            )
        }
    }

    private func resolveAPIKey(from config: AppConfig) -> String {
        let local = config.deepseekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func fetchBalance(apiKey: String, config: AppConfig) async throws -> [QuotaWindow] {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = HTTPClient.makeSession(proxyURL: config.proxyURL, timeout: 12.0)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DeepSeekProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络无有效响应"])
        }
        guard (200...299).contains(http.statusCode) else {
            let reason = Self.friendlyHTTPError(statusCode: http.statusCode, data: data)
            throw NSError(domain: "DeepSeekProvider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason])
        }

        return try Self.parseBalanceJSON(data: data, referenceCap: config.deepseekReferenceCap)
    }

    private static func friendlyHTTPError(statusCode: Int, data: Data) -> String {
        if statusCode == 401 {
            return "API Key 无效或已失效（HTTP 401），请核对是否复制完整且无多余空格"
        }
        if statusCode == 402 {
            return "账户余额不足（HTTP 402）"
        }
        if statusCode == 403 {
            return "请求被拒绝（HTTP 403），若开启了海外代理请将 api.deepseek.com 设为直连"
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String, !msg.isEmpty {
            return "HTTP \(statusCode)：\(msg)"
        }
        return "HTTP 状态码 \(statusCode)"
    }

    static func parseBalanceJSON(data: Data, referenceCap: Double) throws -> [QuotaWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "DeepSeekProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "接口返回非标准 JSON 格式"])
        }

        let isAvailable = (root["is_available"] as? Bool) ?? true
        let infos = (root["balance_infos"] as? [[String: Any]]) ?? []
        let cap = max(referenceCap, 1.0)

        if infos.isEmpty {
            return [
                QuotaWindow(
                    id: "deepseek-empty",
                    label: "账户可用余额（CNY）",
                    kind: .balance(amount: 0.0, currency: "CNY", referenceCap: cap),
                    resetsAt: nil,
                    detail: isAvailable ? "当前余额为 0" : "余额不足"
                )
            ]
        }

        return infos.enumerated().map { idx, info in
            let currency = (info["currency"] as? String) ?? "CNY"
            let total = extractDouble(info["total_balance"]) ?? 0.0
            let granted = extractDouble(info["granted_balance"]) ?? 0.0
            let toppedUp = extractDouble(info["topped_up_balance"]) ?? 0.0
            let symbol = QuotaWindow.currencySymbol(for: currency)
            let detail = String(format: "充值 %@%.2f · 赠送 %@%.2f", symbol, toppedUp, symbol, granted)
            return QuotaWindow(
                id: "deepseek-\(currency)-\(idx)",
                label: "账户可用余额（\(currency)）",
                kind: .balance(amount: total, currency: currency, referenceCap: cap),
                resetsAt: nil,
                detail: isAvailable ? detail : "余额不足 · \(detail)"
            )
        }
    }

    private static func extractDouble(_ raw: Any?) -> Double? {
        if let num = raw as? NSNumber { return num.doubleValue }
        if let str = raw as? String { return Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

// MARK: - OpenCode

struct OpenCodeProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[5]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let fm = FileManager.default
        let configDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode")
        let dataDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")
        let bin = ShellRunner.findExecutable(named: "opencode")
        let customCmd = context.config.opencodeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let installed = bin != nil || fm.fileExists(atPath: configDir.path) || fm.fileExists(atPath: dataDir.path) || !customCmd.isEmpty

        // 1. 本地标准缓存
        if let payload = context.store.readStandardCache(for: descriptor.id) {
            let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
            if !windows.isEmpty {
                let updatedAt = payload.updatedAt.map { Date(timeIntervalSince1970: $0) } ?? now
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: payload.subtitle ?? "本地额度",
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

        // 2. 用户配置的自定义采集命令
        if !customCmd.isEmpty {
            let result = await ShellRunner.runShell(customCmd, timeout: 8.0)
            if result.exitCode == 0,
               let data = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
               let payload = try? JSONDecoder().decode(StandardQuotaPayload.self, from: data) {
                let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
                if !windows.isEmpty {
                    return AgentQuotaSnapshot(
                        id: descriptor.id,
                        name: descriptor.name,
                        badge: payload.subtitle ?? "命令同步",
                        accentHex: descriptor.accentHex,
                        symbolName: descriptor.symbolName,
                        status: .active,
                        windows: windows,
                        sourceLabel: "自定义命令同步",
                        updatedAt: now,
                        isInstalled: true
                    )
                }
            }
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "命令异常",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .error(message: "OpenCode 命令未返回标准额度 JSON"),
                windows: [],
                sourceLabel: "自定义命令",
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
                status: .unavailable(reason: "未检测到本机 OpenCode"),
                windows: [],
                sourceLabel: "本地检测",
                updatedAt: now,
                isInstalled: false
            )
        }

        return AgentQuotaSnapshot(
            id: descriptor.id,
            name: descriptor.name,
            badge: "待配置命令",
            accentHex: descriptor.accentHex,
            symbolName: descriptor.symbolName,
            status: .needsSetup(
                hint: "已检测到本机 OpenCode，可在「设置 → 密钥与代理」填写额度输出命令，或写入 ~/.config/agentbar/cache/opencode.json。",
                action: .openSettings(.credentials)
            ),
            windows: [],
            sourceLabel: "等待配置",
            updatedAt: now,
            isInstalled: true
        )
    }
}
