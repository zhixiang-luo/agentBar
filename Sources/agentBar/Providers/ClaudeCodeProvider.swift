import Foundation

struct ClaudeCodeProvider: QuotaProvider {
    let descriptor = ProviderRegistry.builtInDescriptors[0]

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        let now = Date()
        let fm = FileManager.default
        let claudeDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let installed = fm.fileExists(atPath: claudeDir.path) || ShellRunner.findExecutable(named: "claude") != nil

        // 1. 优先读取官方 statusLine 钩子写入的本地实时缓存
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
                    sourceLabel: "本地状态栏实时同步",
                    updatedAt: updatedAt,
                    isInstalled: true
                )
            }
        }

        guard installed else {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "未安装",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .unavailable(reason: "未检测到本机 Claude Code"),
                windows: [],
                sourceLabel: "本地检测",
                updatedAt: now,
                isInstalled: false
            )
        }

        // 2. 已安装但尚未收到钩子数据
        if ClaudeHookInstaller.isInstalled {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "等待同步",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .needsSetup(
                    hint: "实时采集钩子已就绪，在 Claude Code 发起一次对话后将自动显示 5 小时与周额度。",
                    action: nil
                ),
                windows: [],
                sourceLabel: "等待首次同步",
                updatedAt: now,
                isInstalled: true
            )
        } else {
            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: descriptor.name,
                badge: "待开启同步",
                accentHex: descriptor.accentHex,
                symbolName: descriptor.symbolName,
                status: .needsSetup(
                    hint: "检测到本机已安装 Claude Code，点击下方按钮一键开启零消耗实时额度采集。",
                    action: .installClaudeHook
                ),
                windows: [],
                sourceLabel: "需开启采集钩子",
                updatedAt: now,
                isInstalled: true
            )
        }
    }
}
