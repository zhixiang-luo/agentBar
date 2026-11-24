import Foundation

/// 管理 Claude Code 官方 statusLine 采集钩子，零 API 消耗实时同步 5 小时 / 周额度
enum ClaudeHookInstaller {
    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static var hookScriptURL: URL {
        ConfigStore.shared.scriptsDirectory.appendingPathComponent("claude-statusline-hook.sh")
    }

    private static var originalCommandBackupURL: URL {
        ConfigStore.shared.scriptsDirectory.appendingPathComponent("claude-original-statusline.txt")
    }

    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }
        return command.contains("claude-statusline-hook.sh")
    }

    @discardableResult
    static func install() -> Result<String, Error> {
        do {
            ConfigStore.shared.ensureDirectories()
            let fm = FileManager.default
            let claudeDir = claudeSettingsURL.deletingLastPathComponent()
            try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

            var settings: [String: Any] = [:]
            if let data = try? Data(contentsOf: claudeSettingsURL),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = parsed
            }

            // 如果用户原本配置了自定义 statusLine，先备份以便链式透传
            var originalCommand = ""
            if let existingStatus = settings["statusLine"] as? [String: Any],
               let existingCmd = existingStatus["command"] as? String,
               !existingCmd.contains("claude-statusline-hook.sh") {
                originalCommand = existingCmd
                try originalCommand.write(to: originalCommandBackupURL, atomically: true, encoding: .utf8)
            } else if let saved = try? String(contentsOf: originalCommandBackupURL, encoding: .utf8) {
                originalCommand = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let cachePath = ConfigStore.shared.cacheFileURL(for: "claude-code").path
            let scriptContent = makeHookScript(cachePath: cachePath, chainedCommand: originalCommand)
            try scriptContent.write(to: hookScriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)

            settings["statusLine"] = [
                "type": "command",
                "command": hookScriptURL.path
            ]

            let updatedData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: claudeSettingsURL, options: .atomic)
            return .success("已启用 Claude Code 实时额度采集钩子，下次在 Claude Code 对话后将自动同步 5 小时与周额度。")
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    static func uninstall() -> Result<String, Error> {
        do {
            guard let data = try? Data(contentsOf: claudeSettingsURL),
                  var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .success("未检测到已安装的钩子配置。")
            }

            let savedOriginal = (try? String(contentsOf: originalCommandBackupURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !savedOriginal.isEmpty {
                settings["statusLine"] = [
                    "type": "command",
                    "command": savedOriginal
                ]
            } else {
                settings.removeValue(forKey: "statusLine")
            }

            let updatedData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: claudeSettingsURL, options: .atomic)
            try? FileManager.default.removeItem(at: originalCommandBackupURL)
            return .success("已卸载 Claude Code 额度采集钩子。")
        } catch {
            return .failure(error)
        }
    }

    private static func makeHookScript(cachePath: String, chainedCommand: String) -> String {
        let escapedCache = cachePath.replacingOccurrences(of: "'", with: "'\\''")
        let chainedBlock: String
        if !chainedCommand.isEmpty {
            chainedBlock = """
            printf '%s' "$INPUT" | \(chainedCommand)
            """
        } else {
            chainedBlock = ""
        }

        return """
        #!/bin/zsh
        INPUT=$(cat)
        /usr/bin/python3 -c '
        import json, sys, time, os
        raw = sys.stdin.read()
        try:
            data = json.loads(raw)
        except Exception:
            sys.exit(0)
        rl = data.get("rate_limits") or {}
        windows = []
        five = rl.get("five_hour") or rl.get("session")
        if isinstance(five, dict) and five.get("used_percentage") is not None:
            windows.append({
                "label": "5 小时额度",
                "usedPercent": float(five["used_percentage"]),
                "resetsAt": five.get("resets_at") if isinstance(five.get("resets_at"), (int, float)) else None,
                "resetsAtISO": five.get("resets_at") if isinstance(five.get("resets_at"), str) else None
            })
        seven = rl.get("seven_day") or rl.get("weekly")
        if isinstance(seven, dict) and seven.get("used_percentage") is not None:
            windows.append({
                "label": "周额度",
                "usedPercent": float(seven["used_percentage"]),
                "resetsAt": seven.get("resets_at") if isinstance(seven.get("resets_at"), (int, float)) else None,
                "resetsAtISO": seven.get("resets_at") if isinstance(seven.get("resets_at"), str) else None
            })
        overall = rl.get("all") or rl.get("total") or rl.get("monthly") or rl.get("extra_usage")
        if isinstance(overall, dict) and overall.get("used_percentage") is not None:
            windows.append({
                "label": "全部额度",
                "usedPercent": float(overall["used_percentage"]),
                "resetsAt": overall.get("resets_at") if isinstance(overall.get("resets_at"), (int, float)) else None,
                "resetsAtISO": overall.get("resets_at") if isinstance(overall.get("resets_at"), str) else None
            })
        if windows:
            payload = {
                "subtitle": "订阅额度",
                "updatedAt": time.time(),
                "windows": windows
            }
            target = sys.argv[1]
            os.makedirs(os.path.dirname(target), exist_ok=True)
            tmp = target + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
            os.replace(tmp, target)
        ' '\(escapedCache)' <<< "$INPUT" >/dev/null 2>&1
        \(chainedBlock)
        """
    }
}
