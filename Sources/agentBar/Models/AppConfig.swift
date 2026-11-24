import Foundation

struct AppConfig: Codable, Equatable {
    var enabledBuiltInIDs: [String]
    var providerOrder: [String]
    var enableCustomOrder: Bool
    var hideUnconfiguredProviders: Bool
    var refreshIntervalMinutes: Int
    var showUsedInsteadOfRemaining: Bool
    var appearanceMode: AppAppearanceMode
    var proxyURL: String

    // 内置平台可选密钥与参数
    var deepseekAPIKey: String
    var deepseekReferenceCap: Double
    var cursorAPIKey: String
    var cursorMonthlyBudgetUSD: Double
    var opencodeCommand: String

    static let defaultBuiltInIDs: [String] = [
        "codex",
        "antigravity",
        "claude-code",
        "deepseek",
        "cursor",
        "opencode"
    ]

    static var `default`: AppConfig {
        AppConfig(
            enabledBuiltInIDs: defaultBuiltInIDs,
            providerOrder: defaultBuiltInIDs,
            enableCustomOrder: true,
            hideUnconfiguredProviders: true,
            refreshIntervalMinutes: 3,
            showUsedInsteadOfRemaining: false,
            appearanceMode: .light,
            proxyURL: "",
            deepseekAPIKey: "",
            deepseekReferenceCap: 50.0,
            cursorAPIKey: "",
            cursorMonthlyBudgetUSD: 20.0,
            opencodeCommand: ""
        )
    }

    init(
        enabledBuiltInIDs: [String],
        providerOrder: [String] = defaultBuiltInIDs,
        enableCustomOrder: Bool = true,
        hideUnconfiguredProviders: Bool,
        refreshIntervalMinutes: Int,
        showUsedInsteadOfRemaining: Bool,
        appearanceMode: AppAppearanceMode = .light,
        proxyURL: String,
        deepseekAPIKey: String,
        deepseekReferenceCap: Double,
        cursorAPIKey: String,
        cursorMonthlyBudgetUSD: Double,
        opencodeCommand: String
    ) {
        self.enabledBuiltInIDs = enabledBuiltInIDs
        self.providerOrder = providerOrder
        self.enableCustomOrder = enableCustomOrder
        self.hideUnconfiguredProviders = hideUnconfiguredProviders
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.showUsedInsteadOfRemaining = showUsedInsteadOfRemaining
        self.appearanceMode = appearanceMode
        self.proxyURL = proxyURL
        self.deepseekAPIKey = deepseekAPIKey
        self.deepseekReferenceCap = deepseekReferenceCap
        self.cursorAPIKey = cursorAPIKey
        self.cursorMonthlyBudgetUSD = cursorMonthlyBudgetUSD
        self.opencodeCommand = opencodeCommand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        self.enabledBuiltInIDs = try c.decodeIfPresent([String].self, forKey: .enabledBuiltInIDs) ?? d.enabledBuiltInIDs
        self.providerOrder = try c.decodeIfPresent([String].self, forKey: .providerOrder) ?? d.providerOrder
        self.enableCustomOrder = try c.decodeIfPresent(Bool.self, forKey: .enableCustomOrder) ?? d.enableCustomOrder
        self.hideUnconfiguredProviders = try c.decodeIfPresent(Bool.self, forKey: .hideUnconfiguredProviders) ?? d.hideUnconfiguredProviders
        self.refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? d.refreshIntervalMinutes
        self.showUsedInsteadOfRemaining = try c.decodeIfPresent(Bool.self, forKey: .showUsedInsteadOfRemaining) ?? d.showUsedInsteadOfRemaining
        self.appearanceMode = try c.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? d.appearanceMode
        self.proxyURL = try c.decodeIfPresent(String.self, forKey: .proxyURL) ?? d.proxyURL
        self.deepseekAPIKey = try c.decodeIfPresent(String.self, forKey: .deepseekAPIKey) ?? d.deepseekAPIKey
        self.deepseekReferenceCap = try c.decodeIfPresent(Double.self, forKey: .deepseekReferenceCap) ?? d.deepseekReferenceCap
        self.cursorAPIKey = try c.decodeIfPresent(String.self, forKey: .cursorAPIKey) ?? d.cursorAPIKey
        self.cursorMonthlyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .cursorMonthlyBudgetUSD) ?? d.cursorMonthlyBudgetUSD
        self.opencodeCommand = try c.decodeIfPresent(String.self, forKey: .opencodeCommand) ?? d.opencodeCommand
    }

    func orderIndex(for providerID: String) -> Int {
        guard enableCustomOrder else {
            return Self.defaultBuiltInIDs.firstIndex(of: providerID) ?? 999
        }
        return providerOrder.firstIndex(of: providerID) ?? 999
    }

    func isBuiltInEnabled(_ id: String) -> Bool {
        enabledBuiltInIDs.contains(id)
    }

    mutating func setBuiltIn(_ id: String, enabled: Bool) {
        if enabled {
            if !enabledBuiltInIDs.contains(id) {
                enabledBuiltInIDs.append(id)
            }
        } else {
            enabledBuiltInIDs.removeAll { $0 == id }
        }
    }
}

enum CustomProviderMode: String, Codable, CaseIterable, Identifiable {
    case command
    case httpJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "本地命令（输出标准 JSON）"
        case .httpJSON: return "HTTP 接口（提取余额或额度）"
        }
    }
}

enum CustomHTTPValueKind: String, Codable, CaseIterable, Identifiable {
    case balance
    case usedPercent
    case remainingPercent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: return "账户余额"
        case .usedPercent: return "已用百分比（0-100）"
        case .remainingPercent: return "剩余百分比（0-100）"
        }
    }
}

struct CustomProviderConfig: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var badge: String
    var accentHex: String
    var enabled: Bool
    var mode: CustomProviderMode

    // 命令模式
    var command: String

    // HTTP 模式
    var httpURL: String
    var authHeaderName: String
    var authHeaderPrefix: String
    var authToken: String
    var jsonPath: String
    var windowLabel: String
    var valueKind: CustomHTTPValueKind
    var currency: String
    var balanceCap: Double

    static func commandTemplate() -> CustomProviderConfig {
        CustomProviderConfig(
            id: "custom-\(UUID().uuidString.prefix(6).lowercased())",
            name: "自定义 Agent",
            badge: "命令扩展",
            accentHex: "#38BDF8",
            enabled: true,
            mode: .command,
            command: "cat ~/.config/agentbar/cache/custom-demo.json",
            httpURL: "",
            authHeaderName: "Authorization",
            authHeaderPrefix: "Bearer ",
            authToken: "",
            jsonPath: "",
            windowLabel: "5 小时额度",
            valueKind: .usedPercent,
            currency: "CNY",
            balanceCap: 50.0
        )
    }

    static func httpTemplate() -> CustomProviderConfig {
        CustomProviderConfig(
            id: "custom-\(UUID().uuidString.prefix(6).lowercased())",
            name: "自定义 API 平台",
            badge: "接口余额",
            accentHex: "#A78BFA",
            enabled: true,
            mode: .httpJSON,
            command: "",
            httpURL: "https://api.example.com/v1/balance",
            authHeaderName: "Authorization",
            authHeaderPrefix: "Bearer ",
            authToken: "",
            jsonPath: "data.balance",
            windowLabel: "账户余额",
            valueKind: .balance,
            currency: "CNY",
            balanceCap: 100.0
        )
    }
}

/// 标准额度 JSON 交换格式（用于本地缓存文件与自定义命令输出）
struct StandardQuotaPayload: Codable {
    struct WindowItem: Codable {
        let label: String
        let usedPercent: Double?
        let remainingPercent: Double?
        let balance: Double?
        let currency: String?
        let referenceCap: Double?
        let resetsAt: Double?
        let resetsAtISO: String?
        let detail: String?

        func toQuotaWindow(index: Int) -> QuotaWindow? {
            let resetDate = Self.parseDate(epoch: resetsAt, iso: resetsAtISO)
            if let balance {
                return QuotaWindow(
                    id: "\(label)-\(index)",
                    label: label,
                    kind: .balance(
                        amount: balance,
                        currency: currency ?? "CNY",
                        referenceCap: referenceCap ?? 50.0
                    ),
                    resetsAt: resetDate,
                    detail: detail
                )
            }
            if let usedPercent {
                return QuotaWindow(
                    id: "\(label)-\(index)",
                    label: label,
                    kind: .percentage(usedPercent: usedPercent),
                    resetsAt: resetDate,
                    detail: detail
                )
            }
            if let remainingPercent {
                return QuotaWindow(
                    id: "\(label)-\(index)",
                    label: label,
                    kind: .percentage(usedPercent: max(0, min(100, 100.0 - remainingPercent))),
                    resetsAt: resetDate,
                    detail: detail
                )
            }
            return nil
        }

        static func parseDate(epoch: Double?, iso: String?) -> Date? {
            if let epoch, epoch > 0 {
                let seconds = epoch > 1_000_000_000_000 ? epoch / 1000.0 : epoch
                return Date(timeIntervalSince1970: seconds)
            }
            if let iso, !iso.isEmpty {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: iso) { return parsed }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: iso)
            }
            return nil
        }
    }

    let subtitle: String?
    let updatedAt: Double?
    let windows: [WindowItem]
}
