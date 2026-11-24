import Foundation

/// 面向中国开发者的开箱即用平台预设模板（填入 Key 或命令即可快速导入）
struct ProviderPreset: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let accentHex: String
    let docHint: String
    let template: CustomProviderConfig

    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "preset-siliconflow",
            name: "硅基流动（SiliconFlow）",
            subtitle: "官方账户总余额（CNY）",
            accentHex: "#7C3AED",
            docHint: "在 cloud.siliconflow.cn 控制台获取 API Key",
            template: CustomProviderConfig(
                id: "custom-siliconflow",
                name: "硅基流动",
                badge: "官方余额",
                accentHex: "#7C3AED",
                enabled: true,
                mode: .httpJSON,
                command: "",
                httpURL: "https://api.siliconflow.cn/v1/user/info",
                authHeaderName: "Authorization",
                authHeaderPrefix: "Bearer ",
                authToken: "",
                jsonPath: "data.totalBalance",
                windowLabel: "账户可用余额",
                valueKind: .balance,
                currency: "CNY",
                balanceCap: 100.0
            )
        ),
        ProviderPreset(
            id: "preset-kimi",
            name: "Kimi / Moonshot",
            subtitle: "月之暗面官方 API 余额（CNY）",
            accentHex: "#0EA5E9",
            docHint: "在 platform.moonshot.cn 获取 API Key",
            template: CustomProviderConfig(
                id: "custom-kimi",
                name: "Kimi 开放平台",
                badge: "官方余额",
                accentHex: "#0EA5E9",
                enabled: true,
                mode: .httpJSON,
                command: "",
                httpURL: "https://api.moonshot.cn/v1/users/me/balance",
                authHeaderName: "Authorization",
                authHeaderPrefix: "Bearer ",
                authToken: "",
                jsonPath: "data.available_balance",
                windowLabel: "账户可用余额",
                valueKind: .balance,
                currency: "CNY",
                balanceCap: 100.0
            )
        ),
        ProviderPreset(
            id: "preset-openrouter",
            name: "OpenRouter",
            subtitle: "总充值额度查询（USD）",
            accentHex: "#6366F1",
            docHint: "在 openrouter.ai/keys 获取 API Key",
            template: CustomProviderConfig(
                id: "custom-openrouter",
                name: "OpenRouter",
                badge: "美元额度",
                accentHex: "#6366F1",
                enabled: true,
                mode: .httpJSON,
                command: "",
                httpURL: "https://openrouter.ai/api/v1/credits",
                authHeaderName: "Authorization",
                authHeaderPrefix: "Bearer ",
                authToken: "",
                jsonPath: "data.total_credits",
                windowLabel: "账户总额度",
                valueKind: .balance,
                currency: "USD",
                balanceCap: 50.0
            )
        ),
        ProviderPreset(
            id: "preset-cli",
            name: "自定义 CLI / OpenCode 插件",
            subtitle: "执行本机脚本或命令输出标准额度 JSON",
            accentHex: "#14B8A6",
            docHint: "适合 OpenCode、Qwen Code 或任意自研脚本",
            template: CustomProviderConfig.commandTemplate()
        ),
        ProviderPreset(
            id: "preset-http",
            name: "通用 HTTP 接口 / 中转站",
            subtitle: "对接 OneAPI / NewAPI 或任意 JSON 接口",
            accentHex: "#F97316",
            docHint: "填入 GET 接口地址、鉴权头与 JSON 路径即可",
            template: CustomProviderConfig.httpTemplate()
        )
    ]
}
