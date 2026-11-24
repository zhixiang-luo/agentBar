import AppKit
import Foundation
import SwiftUI

@MainActor
final class AgentBarStore: ObservableObject {
    @Published var config: AppConfig
    @Published var customProviders: [CustomProviderConfig]
    @Published var snapshots: [AgentQuotaSnapshot] = []
    @Published var isRefreshing: Bool = false
    @Published var lastRefreshDate: Date?
    @Published var claudeHookInstalled: Bool
    @Published var statusBannerMessage: String?
    @Published var isPreviewingDemo: Bool = false
    @Published var isSetupDrawerExpanded: Bool = false
    @Published var measuredBodyHeight: CGFloat = 170

    private let store: ConfigStore
    private var refreshTimer: Timer?

    init(store: ConfigStore = .shared, autoStart: Bool = true) {
        self.store = store
        self.config = store.loadConfig()
        self.customProviders = store.loadCustomProviders()
        self.claudeHookInstalled = ClaudeHookInstaller.isInstalled
        NSApp?.appearance = self.config.appearanceMode.nsAppearance
        if autoStart {
            scheduleAutoRefresh()
            Task {
                await refreshAll()
            }
        }
    }

    var activeSnapshots: [AgentQuotaSnapshot] {
        if isPreviewingDemo {
            return Self.demoSnapshots()
        }
        return snapshots.filter {
            switch $0.status {
            case .active, .error: return true
            case .needsSetup, .unavailable: return false
            }
        }
    }

    var setupSnapshots: [AgentQuotaSnapshot] {
        guard !isPreviewingDemo else { return [] }
        return snapshots.filter {
            switch $0.status {
            case .needsSetup: return true
            case .unavailable: return !config.hideUnconfiguredProviders
            case .active, .error: return false
            }
        }
    }

    var visibleSnapshots: [AgentQuotaSnapshot] {
        if isPreviewingDemo {
            return Self.demoSnapshots()
        }
        let filtered = config.hideUnconfiguredProviders
            ? snapshots.filter { $0.status.isVisibleByDefault }
            : snapshots
        // 已同步出额度的卡片永远置顶，待配置卡片排在下方
        return filtered.sorted { lhs, rhs in
            Self.sortRank(lhs.status) < Self.sortRank(rhs.status)
        }
    }

    private static func sortRank(_ status: ProviderStatus) -> Int {
        switch status {
        case .active: return 0
        case .error: return 1
        case .needsSetup: return 2
        case .unavailable: return 3
        }
    }

    var hiddenCount: Int {
        guard !isPreviewingDemo else { return 0 }
        return max(0, snapshots.count - visibleSnapshots.count)
    }

    func snapshot(for id: String) -> AgentQuotaSnapshot? {
        snapshots.first { $0.id == id }
    }

    /// 返回用于设置页展示与拖拽排序的所有平台描述（内置 + 自定义），严格遵循当前排序规则
    var orderedAllDescriptors: [ProviderDescriptor] {
        let customDescs = customProviders.map {
            ProviderDescriptor(
                id: $0.id,
                name: $0.name,
                subtitle: $0.mode.title,
                accentHex: $0.accentHex,
                symbolName: $0.mode == .command ? "terminal" : "globe",
                isCustom: true
            )
        }
        let all = ProviderRegistry.builtInDescriptors + customDescs
        return all.sorted { lhs, rhs in
            config.orderIndex(for: lhs.id) < config.orderIndex(for: rhs.id)
        }
    }

    func ensureOrderContainsAllProviders() {
        let allIDs = (ProviderRegistry.builtInDescriptors.map(\.id) + customProviders.map(\.id))
        var order = config.providerOrder.filter { allIDs.contains($0) }
        for id in allIDs where !order.contains(id) {
            order.append(id)
        }
        if order != config.providerOrder {
            config.providerOrder = order
        }
    }

    func moveProvider(fromID: String, toID: String) {
        guard config.enableCustomOrder, fromID != toID else { return }
        ensureOrderContainsAllProviders()
        guard let fromIdx = config.providerOrder.firstIndex(of: fromID),
              let toIdx = config.providerOrder.firstIndex(of: toID) else { return }
        let item = config.providerOrder.remove(at: fromIdx)
        config.providerOrder.insert(item, at: toIdx)
        applyOrderingToSnapshots()
        store.saveConfig(config)
    }

    func nudgeProvider(id: String, direction: Int) {
        guard config.enableCustomOrder else { return }
        ensureOrderContainsAllProviders()
        guard let idx = config.providerOrder.firstIndex(of: id) else { return }
        let target = idx + direction
        guard config.providerOrder.indices.contains(target) else { return }
        config.providerOrder.swapAt(idx, target)
        applyOrderingToSnapshots()
        store.saveConfig(config)
    }

    func applyOrderingToSnapshots() {
        snapshots.sort { lhs, rhs in
            config.orderIndex(for: lhs.id) < config.orderIndex(for: rhs.id)
        }
    }

    func saveConfig() {
        ensureOrderContainsAllProviders()
        store.saveConfig(config)
        NSApp?.appearance = config.appearanceMode.nsAppearance
        SettingsWindowController.shared.applyAppearance(config.appearanceMode)
        applyOrderingToSnapshots()
        scheduleAutoRefresh()
        Task {
            await refreshAll()
        }
    }

    func saveCustomProviders() {
        store.saveCustomProviders(customProviders)
        Task {
            await refreshAll()
        }
    }

    func toggleDisplayMode() {
        config.showUsedInsteadOfRemaining.toggle()
        store.saveConfig(config)
    }

    func installClaudeHook() {
        switch ClaudeHookInstaller.install() {
        case .success(let message):
            claudeHookInstalled = ClaudeHookInstaller.isInstalled
            statusBannerMessage = message
        case .failure(let error):
            statusBannerMessage = "安装钩子失败：\(error.localizedDescription)"
        }
        Task {
            await refreshAll()
        }
    }

    func uninstallClaudeHook() {
        switch ClaudeHookInstaller.uninstall() {
        case .success(let message):
            claudeHookInstalled = ClaudeHookInstaller.isInstalled
            statusBannerMessage = message
        case .failure(let error):
            statusBannerMessage = "卸载钩子失败：\(error.localizedDescription)"
        }
        Task {
            await refreshAll()
        }
    }

    func refreshIfStale(maxAgeSeconds: TimeInterval = 20) {
        if snapshots.isEmpty {
            Task { await refreshAll() }
            return
        }
        if let last = lastRefreshDate, Date().timeIntervalSince(last) >= maxAgeSeconds {
            Task { await refreshAll() }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        claudeHookInstalled = ClaudeHookInstaller.isInstalled

        let currentConfig = config
        let currentCustom = customProviders
        let providers = ProviderRegistry.activeProviders(
            config: currentConfig,
            customConfigs: currentCustom
        )
        let context = ProviderContext(config: currentConfig, store: store)

        let results: [AgentQuotaSnapshot] = await withTaskGroup(
            of: (Int, AgentQuotaSnapshot).self
        ) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let snap = await provider.fetch(context: context)
                    return (index, snap)
                }
            }
            var indexed: [(Int, AgentQuotaSnapshot)] = []
            for await item in group {
                indexed.append(item)
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        self.snapshots = results
        self.lastRefreshDate = Date()
        self.isRefreshing = false
    }

    func testCustomProvider(_ custom: CustomProviderConfig) async -> AgentQuotaSnapshot {
        let context = ProviderContext(config: config, store: store)
        return await CustomProvider(config: custom).fetch(context: context)
    }

    func testDeepSeek() async -> AgentQuotaSnapshot {
        store.saveConfig(config)
        let context = ProviderContext(config: config, store: store)
        return await DeepSeekProvider().fetch(context: context)
    }

    private func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        let seconds = TimeInterval(max(1, config.refreshIntervalMinutes) * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
    }

    /// 示例效果卡片（方便首次打开尚未配置平台的用户预览实际额度条效果）
    static func demoSnapshots(now: Date = Date()) -> [AgentQuotaSnapshot] {
        [
            AgentQuotaSnapshot(
                id: "demo-codex",
                name: "Codex",
                badge: "示例 · Plus",
                accentHex: "#10A37F",
                symbolName: "terminal.fill",
                status: .active,
                windows: [
                    QuotaWindow(
                        id: "demo-codex-5h",
                        label: "5 小时额度",
                        kind: .percentage(usedPercent: 18),
                        resetsAt: now.addingTimeInterval(3 * 3600 + 42 * 60)
                    ),
                    QuotaWindow(
                        id: "demo-codex-week",
                        label: "周额度",
                        kind: .percentage(usedPercent: 64),
                        resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)
                    )
                ],
                sourceLabel: "示例数据",
                updatedAt: now,
                isInstalled: true
            ),
            AgentQuotaSnapshot(
                id: "demo-antigravity",
                name: "Antigravity（反重力）",
                badge: "示例 · CLI",
                accentHex: "#4285F4",
                symbolName: "atom",
                status: .active,
                windows: [
                    QuotaWindow(
                        id: "demo-agy-5h",
                        label: "5 小时额度",
                        kind: .percentage(usedPercent: 86),
                        resetsAt: now.addingTimeInterval(52 * 60)
                    ),
                    QuotaWindow(
                        id: "demo-agy-week",
                        label: "周额度",
                        kind: .percentage(usedPercent: 32),
                        resetsAt: now.addingTimeInterval(5 * 86400)
                    )
                ],
                sourceLabel: "示例数据",
                updatedAt: now,
                isInstalled: true
            ),
            AgentQuotaSnapshot(
                id: "demo-deepseek",
                name: "DeepSeek",
                badge: "示例 · 余额",
                accentHex: "#4D6BFE",
                symbolName: "waveform.path.ecg",
                status: .active,
                windows: [
                    QuotaWindow(
                        id: "demo-ds-bal",
                        label: "账户可用余额（CNY）",
                        kind: .balance(amount: 36.80, currency: "CNY", referenceCap: 50.0),
                        resetsAt: nil,
                        detail: "充值 ¥35.00 · 赠送 ¥1.80"
                    )
                ],
                sourceLabel: "示例数据",
                updatedAt: now,
                isInstalled: true
            )
        ]
    }
}
