import Foundation

struct AntigravityProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[2]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let fm = FileManager.default
        let agyConfigDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
        let agyCLIConfigDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity-cli", isDirectory: true)
        let agyBin = ShellRunner.findExecutable(named: "agy")
        let installed = agyBin != nil
            || fm.fileExists(atPath: agyConfigDir.path)
            || fm.fileExists(atPath: agyCLIConfigDir.path)

        // 1. 优先读取标准本地缓存（支持通过外部脚本/钩子推送）
        if let payload = context.store.readStandardCache(for: descriptor.id) {
            let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
            if !windows.isEmpty {
                let updatedAt = payload.updatedAt.map { Date(timeIntervalSince1970: $0) } ?? now
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: payload.subtitle ?? "模型额度",
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

        // 2. 已安装官方 agy CLI：通过公开命令行参数查询实时额度 JSON
        if let agyBin {
            let escaped = agyBin.replacingOccurrences(of: "'", with: "'\\''")
            let result = await ShellRunner.runShell("'\(escaped)' --print /usage --output-format json", timeout: 22.0)
            if result.exitCode == 0, let windows = Self.parseAgyUsageJSON(result.stdout), !windows.isEmpty {
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: "官方 CLI",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .active,
                    windows: windows,
                    sourceLabel: "agy 命令行实时同步",
                    updatedAt: now,
                    isInstalled: true
                )
            }

            if result.exitCode != 0 {
                return AgentQuotaSnapshot(
                    id: descriptor.id,
                    name: descriptor.name,
                    badge: "需登录 agy",
                    accentHex: descriptor.accentHex,
                    symbolName: descriptor.symbolName,
                    status: .needsSetup(
                        hint: "已安装 agy 命令行，但尚未拿到额度。请在终端运行一次 agy 完成账号登录，再点刷新。",
                        action: .copyCommand(title: "复制登录命令", command: "agy")
                    ),
                    windows: [],
                    sourceLabel: "agy 命令行",
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
                status: .unavailable(reason: "未检测到本机 Antigravity"),
                windows: [],
                sourceLabel: "本地检测",
                updatedAt: now,
                isInstalled: false
            )
        }

        return AgentQuotaSnapshot(
            id: descriptor.id,
            name: descriptor.name,
            badge: "需安装 agy CLI",
            accentHex: descriptor.accentHex,
            symbolName: descriptor.symbolName,
            status: .needsSetup(
                hint: "已检测到 Antigravity，但本机尚未安装官方 agy 命令行。安装并登录 agy 后即可自动实时同步额度。",
                action: .copyCommand(
                    title: "复制 agy 安装命令",
                    command: "brew install --cask antigravity-cli"
                )
            ),
            windows: [],
            sourceLabel: "等待 agy 命令行",
            updatedAt: now,
            isInstalled: true
        )
    }

    /// 完整解析 agy `--print /usage --output-format json` 返回的 JSON 结构：
    /// - 过滤掉第三方 Claude / GPT 模型组，只展示反重力核心额度
    /// - 普通会员展示「5 小时额度」与「周额度」
    /// - 最高档会员（无 5 小时额度或 5h 为 disabled）自动展示「周额度」与其余全部有效额度
    static func parseAgyUsageJSON(_ raw: String) -> [QuotaWindow]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let standard = try? JSONDecoder().decode(StandardQuotaPayload.self, from: data) {
            let mapped = standard.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
            if !mapped.isEmpty { return mapped }
        }

        guard let dict = json as? [String: Any] else { return nil }

        // 真实 agy CLI 结构：command.data.groups[].buckets[]
        if let command = dict["command"] as? [String: Any],
           let cmdData = command["data"] as? [String: Any],
           let groups = cmdData["groups"] as? [[String: Any]] {
            // 仅保留反重力自身主模型组（排除 Claude / GPT 第三方组）
            let coreGroups = groups.filter { group in
                let name = ((group["name"] as? String) ?? "").lowercased()
                return !name.contains("claude") && !name.contains("gpt")
            }

            let targetGroups = coreGroups.isEmpty ? groups : coreGroups
            let useGroupPrefix = targetGroups.count > 1

            var groupedWindows: [QuotaWindow] = []
            for (gIdx, group) in targetGroups.enumerated() {
                let rawGroupName = (group["name"] as? String) ?? "模型组 \(gIdx + 1)"
                let groupName = localizeGroupName(rawGroupName)
                guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

                // 组内排序：5 小时额度 -> 周额度 -> 全部/月度/其他额度
                let sortedBuckets = buckets.sorted { lhs, rhs in
                    bucketRank(lhs["window"] as? String, name: lhs["name"] as? String)
                        < bucketRank(rhs["window"] as? String, name: rhs["name"] as? String)
                }

                for (bIdx, bucket) in sortedBuckets.enumerated() {
                    if let disabled = bucket["disabled"] as? Bool, disabled {
                        continue
                    }
                    let windowKey = (bucket["window"] as? String) ?? (bucket["name"] as? String) ?? ""
                    let windowTitle = localizeWindowName(windowKey, fallbackName: bucket["name"] as? String)
                    let fullLabel = useGroupPrefix ? "\(groupName) · \(windowTitle)" : windowTitle
                    let bucketID = (bucket["id"] as? String) ?? "agy-g\(gIdx)-b\(bIdx)"
                    if let win = buildWindow(from: bucket, label: fullLabel, id: bucketID) {
                        groupedWindows.append(win)
                    }
                }
            }

            if !groupedWindows.isEmpty {
                return groupedWindows
            }
        }

        var windows: [QuotaWindow] = []

        // 兼容结构 A：five_hour / seven_day / weekly / all
        let pairs: [(keys: [String], label: String)] = [
            (["five_hour", "fiveHour", "session", "primary"], "5 小时额度"),
            (["seven_day", "sevenDay", "weekly", "secondary"], "周额度"),
            (["all", "total", "overall", "monthly"], "全部额度")
        ]

        for (index, item) in pairs.enumerated() {
            for key in item.keys {
                if let sub = dict[key] as? [String: Any],
                   (sub["disabled"] as? Bool) != true,
                   let win = buildWindow(from: sub, label: item.label, id: "agy-\(index)") {
                    windows.append(win)
                    break
                }
            }
        }

        // 兼容结构 B：models / quotas / buckets 数组
        let arrayKeys = ["quotas", "models", "buckets"]
        for key in arrayKeys {
            if let list = dict[key] as? [[String: Any]] {
                for (idx, item) in list.enumerated() {
                    if let disabled = item["disabled"] as? Bool, disabled { continue }
                    let rawLabel = (item["label"] as? String)
                        ?? (item["name"] as? String)
                        ?? (item["model"] as? String)
                        ?? "全部额度"
                    let lower = rawLabel.lowercased()
                    if lower.contains("claude") || lower.contains("gpt") { continue }
                    if let win = buildWindow(from: item, label: localizeWindowName(rawLabel, fallbackName: nil), id: "agy-m-\(idx)") {
                        windows.append(win)
                    }
                }
            }
        }

        return windows.isEmpty ? nil : windows
    }

    private static func buildWindow(from dict: [String: Any], label: String, id: String) -> QuotaWindow? {
        let usedPct: Double?
        if let used = extractNumber(dict["used_percentage"]) ?? extractNumber(dict["usedPercent"]) ?? extractNumber(dict["used_percent"]) {
            usedPct = used
        } else if let rem = extractNumber(dict["remaining_percentage"]) ?? extractNumber(dict["remainingPercent"]) {
            usedPct = max(0, min(100, 100.0 - rem))
        } else if let frac = extractNumber(dict["remainingFraction"]) ?? extractNumber(dict["remaining_fraction"]) {
            usedPct = max(0, min(100, (1.0 - frac) * 100.0))
        } else {
            usedPct = nil
        }

        guard let usedPct else { return nil }
        let resetEpoch = extractNumber(dict["resets_at"]) ?? extractNumber(dict["resetsAt"]) ?? extractNumber(dict["reset_at"])
        let resetISO = (dict["resets_at"] as? String)
            ?? (dict["resetsAt"] as? String)
            ?? (dict["resetTime"] as? String)
            ?? (dict["reset_time"] as? String)
        let resetDate = StandardQuotaPayload.WindowItem.parseDate(epoch: resetEpoch, iso: resetISO)

        return QuotaWindow(
            id: id,
            label: label,
            kind: .percentage(usedPercent: usedPct),
            resetsAt: resetDate
        )
    }

    private static func bucketRank(_ window: String?, name: String?) -> Int {
        let lower = ((window ?? "") + " " + (name ?? "")).lowercased()
        if lower.contains("5h") || lower.contains("five") || lower.contains("5-hour") { return 0 }
        if lower.contains("week") || lower.contains("7d") { return 1 }
        return 2
    }

    private static func localizeGroupName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("gemini") { return "Gemini" }
        return raw
    }

    private static func localizeWindowName(_ raw: String, fallbackName: String?) -> String {
        let combined = (raw + " " + (fallbackName ?? "")).lowercased()
        if combined.contains("5h") || combined.contains("5-hour") || combined.contains("five_hour") || combined.contains("five hour") {
            return "5 小时额度"
        }
        if combined.contains("week") || combined.contains("7d") || combined.contains("seven_day") {
            return "周额度"
        }
        if combined.contains("month") || combined.contains("30d") {
            return "月度额度"
        }
        if combined.contains("all") || combined.contains("total") || combined.contains("overall") || combined.contains("credit") {
            return "全部额度"
        }
        return raw.isEmpty ? "全部额度" : raw
    }

    private static func extractNumber(_ value: Any?) -> Double? {
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String { return Double(str) }
        return nil
    }
}
