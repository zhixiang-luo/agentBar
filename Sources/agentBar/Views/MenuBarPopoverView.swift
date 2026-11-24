import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: AgentBarStore

    private var theme: ThemePalette {
        ThemePalette(colorScheme: colorScheme, appearanceMode: store.config.appearanceMode)
    }

    // 默认舒适展示最多 3 张平台卡片（约 520pt），超过 3 张自动出现滚动条
    private let maxBodyHeight: CGFloat = 520
    private let chromeHeight: CGFloat = 79

    private var clampedBodyHeight: CGFloat {
        let raw = max(store.measuredBodyHeight, 120)
        return min(raw, maxBodyHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            HairlineDivider(color: theme.divider)

            // 始终保持单一 ScrollView 视图树 + 实时测量真实内容高度，
            // 配合顶部锚定的窗口尺寸更新，展开与收起绝不出现上方透明空白
            ScrollView(.vertical, showsIndicators: store.measuredBodyHeight > maxBodyHeight) {
                popoverContent
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .frame(height: clampedBodyHeight)
            .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                if height > 20, abs(height - store.measuredBodyHeight) > 1 {
                    store.measuredBodyHeight = height
                }
            }

            HairlineDivider(color: theme.divider)

            footerBar
        }
        .frame(width: 332, height: clampedBodyHeight + chromeHeight, alignment: .top)
        .background(
            ZStack {
                VisualEffectBackground(
                    material: .popover,
                    blendingMode: .behindWindow,
                    appearanceMode: store.config.appearanceMode,
                    targetWindowHeight: clampedBodyHeight + chromeHeight
                )
                theme.canvasTint
            }
            .ignoresSafeArea()
        )
        .onAppear {
            store.refreshIfStale(maxAgeSeconds: 20)
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 10) {
            if let banner = store.statusBannerMessage {
                statusBanner(banner)
            }

            if store.isPreviewingDemo {
                demoPreviewBanner
            }

            if store.activeSnapshots.isEmpty {
                quickOnboardingCard

                if !store.setupSnapshots.isEmpty {
                    setupDrawerToggle
                    if store.isSetupDrawerExpanded {
                        ForEach(store.setupSnapshots) { snapshot in
                            AgentQuotaCardView(
                                snapshot: snapshot,
                                showUsed: store.config.showUsedInsteadOfRemaining,
                                theme: theme,
                                onAction: handleSetupAction
                            )
                        }
                    }
                }
            } else {
                ForEach(store.activeSnapshots) { snapshot in
                    AgentQuotaCardView(
                        snapshot: snapshot,
                        showUsed: store.config.showUsedInsteadOfRemaining,
                        theme: theme,
                        onAction: handleSetupAction
                    )
                }

                if !store.setupSnapshots.isEmpty {
                    setupDrawerToggle
                    if store.isSetupDrawerExpanded {
                        ForEach(store.setupSnapshots) { snapshot in
                            AgentQuotaCardView(
                                snapshot: snapshot,
                                showUsed: store.config.showUsedInsteadOfRemaining,
                                theme: theme,
                                onAction: handleSetupAction
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var setupDrawerToggle: some View {
        Button {
            store.isSetupDrawerExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.isSetupDrawerExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Text("其他待接入平台（\(store.setupSnapshots.count)）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text(store.isSetupDrawerExpanded ? "收起" : "展开")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.actionBlue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: theme.cardShadowColor, radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 极简原生顶栏（原型同款仪表盘图标 + 刷新 + 设置，无主题切换按钮）

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                MinimalGaugeIcon(size: 14, lineWidth: 1.75)
                    .foregroundStyle(theme.textPrimary.opacity(0.8))
                Text("agentBar")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(theme.textPrimary)
            }

            Spacer()

            Text(store.isRefreshing ? "刷新中…" : QuotaTimeFormatter.relativeUpdateText(from: store.lastRefreshDate))
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .padding(.trailing, 2)

            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(
                        store.isRefreshing
                            ? .linear(duration: 0.85).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
                    .frame(width: 22, height: 22)
                    .background(theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("刷新全部额度")

            Button {
                SettingsWindowController.shared.open(store: store, initialTab: .providers)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("打开设置")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    // MARK: - 提示条与示例预览条

    private func statusBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.healthColor(for: .good))
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                store.statusBannerMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(theme.bannerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.bannerBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var demoPreviewBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 11))
                .foregroundStyle(theme.actionBlue)
            Text("示例效果预览（非真实账户额度）")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Button("退出预览") {
                store.isPreviewingDemo = false
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.actionBlue)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.actionBlue.opacity(0.28), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - 零懵逼新手快速接入卡片

    private var quickOnboardingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("快速接入你的 AI 平台")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("已自动隐藏未安装平台，点下方按钮几秒完成导入")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            HairlineDivider(color: theme.divider)

            VStack(spacing: 9) {
                onboardingRow(
                    title: "Codex / Claude Code",
                    subtitle: "自动读取本机登录态或一键开启钩子",
                    buttonTitle: "去开启",
                    accent: Color(hex: "#10A37F")
                ) {
                    SettingsWindowController.shared.open(store: store, initialTab: .providers)
                }

                onboardingRow(
                    title: "Antigravity（反重力）",
                    subtitle: "安装官方 agy CLI 自动同步",
                    buttonTitle: "复制命令",
                    accent: Color(hex: "#3B82F6")
                ) {
                    handleSetupAction(.copyCommand(title: "复制命令", command: "brew install --cask antigravity-cli"))
                }

                onboardingRow(
                    title: "DeepSeek / Cursor",
                    subtitle: "填入 API Key 即看实时余额与预算",
                    buttonTitle: "填密钥",
                    accent: Color(hex: "#4D6BFE")
                ) {
                    SettingsWindowController.shared.open(store: store, initialTab: .credentials)
                }

                onboardingRow(
                    title: "硅基流动 / Kimi / OpenCode / 其他",
                    subtitle: "支持一键模板与命令/接口扩展",
                    buttonTitle: "+ 导入",
                    accent: Color(hex: "#EC4899")
                ) {
                    SettingsWindowController.shared.open(store: store, initialTab: .extensions)
                }
            }

            HStack {
                Button("先看一眼额度卡片效果") {
                    store.isPreviewingDemo = true
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.actionBlue)
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 1)
        }
        .padding(13)
        .background(theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(theme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: theme.cardShadowColor, radius: 4, x: 0, y: 1.5)
    }

    private func onboardingRow(
        title: String,
        subtitle: String,
        buttonTitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
        }
    }

    // MARK: - 极简底栏

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                store.toggleDisplayMode()
            } label: {
                Text(store.config.showUsedInsteadOfRemaining ? "显示：已用" : "显示：剩余")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("点击切换「剩余百分比」或「已用百分比」")

            Spacer()

            Button("+ 导入平台") {
                SettingsWindowController.shared.open(store: store, initialTab: .extensions)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.textSecondary)
            .buttonStyle(.plain)

            Text("·")
                .foregroundStyle(theme.textMuted)

            Button("退出") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.textMuted)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func handleSetupAction(_ action: SetupAction) {
        switch action {
        case .installClaudeHook:
            store.installClaudeHook()
        case .copyCommand(_, let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            store.statusBannerMessage = "已复制安装命令到剪贴板，在终端粘贴运行并登录后，点右上角刷新即可。"
        case .openSettings(let tab):
            SettingsWindowController.shared.open(store: store, initialTab: tab)
        }
    }
}

// MARK: - macOS 原生简约额度卡片

struct AgentQuotaCardView: View {
    let snapshot: AgentQuotaSnapshot
    let showUsed: Bool
    let theme: ThemePalette
    let onAction: (SetupAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Circle()
                    .fill(snapshot.accentColor)
                    .frame(width: 7.5, height: 7.5)

                Text(snapshot.name)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(snapshot.badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(theme.cardElevated)
                    .clipShape(Capsule())
            }

            switch snapshot.status {
            case .active:
                VStack(spacing: 11) {
                    ForEach(snapshot.windows) { window in
                        QuotaWindowRowView(window: window, showUsed: showUsed, theme: theme)
                    }
                }

            case .needsSetup(let hint, let action):
                VStack(alignment: .leading, spacing: 8) {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action {
                        Button {
                            onAction(action)
                        } label: {
                            Text(actionTitle(for: action))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(snapshot.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(snapshot.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .unavailable(let reason):
                Text(reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textMuted)

            case .error(let message):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.healthColor(for: .critical))
                        .padding(.top, 1)
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.errorText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .background(theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: theme.cardShadowColor, radius: 3.5, x: 0, y: 1.5)
    }

    private var cardBorderColor: Color {
        switch snapshot.status {
        case .error:
            return theme.healthColor(for: .critical).opacity(0.32)
        default:
            return theme.border
        }
    }

    private func actionTitle(for action: SetupAction) -> String {
        switch action {
        case .installClaudeHook:
            return "一键开启实时额度同步"
        case .copyCommand(let title, _):
            return title
        case .openSettings:
            return "前往设置配置"
        }
    }
}

struct QuotaWindowRowView: View {
    let window: QuotaWindow
    let showUsed: Bool
    let theme: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5.5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Text(window.formattedPrimaryValue(showUsed: showUsed))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.healthColor(for: window.health))
            }

            GeometryReader { geo in
                let progress = min(max(window.barProgress(showUsed: showUsed), 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.track)
                        .frame(height: 6)

                    Capsule()
                        .fill(theme.healthColor(for: window.health))
                        .frame(width: max(progress > 0 ? 6 : 0, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)

            if let metaLine = metadataLine {
                Text(metaLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private var metadataLine: String? {
        let reset = QuotaTimeFormatter.resetDescription(for: window.resetsAt)
        switch (reset, window.detail) {
        case let (r?, d?) where !d.isEmpty:
            return "\(r) · \(d)"
        case let (r?, _):
            return r
        case let (_, d?) where !d.isEmpty:
            return d
        default:
            return nil
        }
    }
}
