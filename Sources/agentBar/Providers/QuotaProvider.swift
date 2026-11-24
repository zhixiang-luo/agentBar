import Foundation

struct ProviderDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let accentHex: String
    let symbolName: String
    let isCustom: Bool
}

struct ProviderContext {
    let config: AppConfig
    let store: ConfigStore
}

protocol QuotaProvider {
    var descriptor: ProviderDescriptor { get }
    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot
}

enum ProviderRegistry {
    static let builtInDescriptors: [ProviderDescriptor] = [
        ProviderDescriptor(
            id: "claude-code",
            name: "Claude Code",
            subtitle: "5 小时 / 周滚动额度",
            accentHex: "#D97757",
            symbolName: "sparkles",
            isCustom: false
        ),
        ProviderDescriptor(
            id: "codex",
            name: "Codex",
            subtitle: "5 小时 / 周滚动额度",
            accentHex: "#10A37F",
            symbolName: "terminal.fill",
            isCustom: false
        ),
        ProviderDescriptor(
            id: "antigravity",
            name: "Antigravity（反重力）",
            subtitle: "5 小时 / 周模型额度",
            accentHex: "#4285F4",
            symbolName: "atom",
            isCustom: false
        ),
        ProviderDescriptor(
            id: "cursor",
            name: "Cursor",
            subtitle: "月度用量额度",
            accentHex: "#38BDF8",
            symbolName: "cursorarrow.rays",
            isCustom: false
        ),
        ProviderDescriptor(
            id: "deepseek",
            name: "DeepSeek",
            subtitle: "官方 API 账户余额",
            accentHex: "#4D6BFE",
            symbolName: "waveform.path.ecg",
            isCustom: false
        ),
        ProviderDescriptor(
            id: "opencode",
            name: "OpenCode",
            subtitle: "本地 CLI / 扩展额度",
            accentHex: "#F472B6",
            symbolName: "chevron.left.forwardslash.chevron.right",
            isCustom: false
        )
    ]

    static func activeProviders(
        config: AppConfig,
        customConfigs: [CustomProviderConfig]
    ) -> [any QuotaProvider] {
        let allBuiltIns: [any QuotaProvider] = [
            ClaudeCodeProvider(),
            CodexProvider(),
            AntigravityProvider(),
            CursorProvider(),
            DeepSeekProvider(),
            OpenCodeProvider()
        ]

        var result: [any QuotaProvider] = allBuiltIns.filter {
            config.isBuiltInEnabled($0.descriptor.id)
        }

        let enabledCustom = customConfigs
            .filter { $0.enabled }
            .map { CustomProvider(config: $0) }
        result.append(contentsOf: enabledCustom)

        if config.enableCustomOrder {
            result.sort { lhs, rhs in
                config.orderIndex(for: lhs.descriptor.id) < config.orderIndex(for: rhs.descriptor.id)
            }
        }

        return result
    }
}
