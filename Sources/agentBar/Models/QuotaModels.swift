import Foundation
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Codable {
    case providers
    case credentials
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: return "平台管理"
        case .credentials: return "密钥与代理"
        case .extensions: return "扩展平台"
        }
    }
}

enum QuotaHealth: String, Codable {
    case good
    case warning
    case critical
    case neutral

    var color: Color {
        switch self {
        case .good: return Color(hex: "#22C55E")
        case .warning: return Color(hex: "#F59E0B")
        case .critical: return Color(hex: "#EF4444")
        case .neutral: return Color(hex: "#64748B")
        }
    }
}

enum QuotaWindowKind: Codable, Equatable {
    /// 百分比型（如 5 小时额度、周额度）
    case percentage(usedPercent: Double)
    /// 余额型（如 DeepSeek API 余额、中转站余额）
    case balance(amount: Double, currency: String, referenceCap: Double)
}

struct QuotaWindow: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let kind: QuotaWindowKind
    let resetsAt: Date?
    let detail: String?

    init(
        id: String = UUID().uuidString,
        label: String,
        kind: QuotaWindowKind,
        resetsAt: Date? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.resetsAt = resetsAt
        self.detail = detail
    }

    /// 剩余比例 (0.0 ... 1.0)
    var remainingRatio: Double {
        switch kind {
        case .percentage(let usedPercent):
            let clamped = min(max(usedPercent, 0), 100)
            return (100.0 - clamped) / 100.0
        case .balance(let amount, _, let referenceCap):
            guard referenceCap > 0 else { return amount > 0 ? 1.0 : 0.0 }
            return min(max(amount / referenceCap, 0), 1.0)
        }
    }

    /// 已用比例 (0.0 ... 1.0)
    var usedRatio: Double {
        1.0 - remainingRatio
    }

    var remainingPercent: Double {
        remainingRatio * 100.0
    }

    var usedPercent: Double {
        usedRatio * 100.0
    }

    var health: QuotaHealth {
        let ratio = remainingRatio
        if ratio <= 0.20 {
            return .critical
        } else if ratio <= 0.50 {
            return .warning
        } else {
            return .good
        }
    }

    func formattedPrimaryValue(showUsed: Bool) -> String {
        switch kind {
        case .percentage:
            if showUsed {
                return "已用 \(Int(round(usedPercent)))%"
            } else {
                return "剩余 \(Int(round(remainingPercent)))%"
            }
        case .balance(let amount, let currency, _):
            let symbol = Self.currencySymbol(for: currency)
            return String(format: "%@%.2f", symbol, amount)
        }
    }

    func barProgress(showUsed: Bool) -> Double {
        switch kind {
        case .percentage:
            return showUsed ? usedRatio : remainingRatio
        case .balance:
            return remainingRatio
        }
    }

    static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        default: return "\(code) "
        }
    }
}

enum SetupAction: Equatable {
    case installClaudeHook
    case copyCommand(title: String, command: String)
    case openSettings(SettingsTab)
}

enum ProviderStatus: Equatable {
    case active
    case needsSetup(hint: String, action: SetupAction?)
    case unavailable(reason: String)
    case error(message: String)

    var isVisibleByDefault: Bool {
        switch self {
        case .active, .needsSetup, .error:
            return true
        case .unavailable:
            return false
        }
    }
}

struct AgentQuotaSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let badge: String
    let accentHex: String
    let symbolName: String
    let status: ProviderStatus
    let windows: [QuotaWindow]
    let sourceLabel: String
    let updatedAt: Date
    let isInstalled: Bool

    var accentColor: Color {
        Color(hex: accentHex)
    }

    /// 卡片整体健康度（取最紧迫的额度窗口）
    var worstHealth: QuotaHealth {
        guard !windows.isEmpty else { return .neutral }
        if windows.contains(where: { $0.health == .critical }) { return .critical }
        if windows.contains(where: { $0.health == .warning }) { return .warning }
        return .good
    }
}

enum QuotaTimeFormatter {
    static func resetDescription(
        for date: Date?,
        now: Date = Date(),
        windowLabel: String? = nil
    ) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 60 {
            return "即将重置"
        }

        let totalMinutes = Int(interval / 60)
        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = totalHours / 24
        let remHours = totalHours % 24
        let isMonthly = (windowLabel ?? "").contains("月")

        // 月度周期（>= 1 天）：直接显示“本月还剩 X 天重置”
        if isMonthly && days >= 1 {
            let displayDays = remHours >= 12 ? days + 1 : days
            return "本月还剩 \(displayDays) 天重置"
        }

        if totalHours < 24 {
            if totalHours == 0 {
                return "还剩 \(minutes) 分钟重置"
            } else if minutes == 0 {
                return "还剩 \(totalHours) 小时重置"
            } else {
                return "还剩 \(totalHours) 小时 \(minutes) 分钟重置"
            }
        }

        // 周额度 / 跨天周期：直接显示“还剩 X 天 Y 小时重置”
        if remHours == 0 {
            return "还剩 \(days) 天重置"
        } else {
            return "还剩 \(days) 天 \(remHours) 小时重置"
        }
    }

    static func relativeUpdateText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "尚未刷新" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 15 {
            return "刚刚更新"
        } else if seconds < 60 {
            return "\(seconds) 秒前更新"
        } else if seconds < 3600 {
            return "\(seconds / 60) 分钟前更新"
        } else {
            return "\(seconds / 3600) 小时前更新"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.35
            g = 0.55
            b = 0.95
        }
        self.init(red: r, green: g, blue: b)
    }
}
