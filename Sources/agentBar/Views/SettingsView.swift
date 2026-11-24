import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab
    @Published var editorViewModel: CustomEditorViewModel?
    @Published var isPresentingEditor: Bool = false
    @Published var deepseekTestMessage: String?
    @Published var deepseekTestIsSuccess: Bool = false
    @Published var isTestingDeepSeek: Bool = false
    @Published var draggingProviderID: String?

    init(selectedTab: SettingsTab = .providers) {
        self.selectedTab = selectedTab
    }

    func startEditing(_ config: CustomProviderConfig, docHint: String? = nil) {
        editorViewModel = CustomEditorViewModel(draft: config, docHint: docHint)
        isPresentingEditor = true
    }

    func closeEditor() {
        isPresentingEditor = false
        editorViewModel = nil
    }
}

@MainActor
final class CustomEditorViewModel: ObservableObject {
    @Published var draft: CustomProviderConfig
    @Published var docHint: String?
    @Published var testStatus: String?
    @Published var isTesting: Bool = false

    init(draft: CustomProviderConfig, docHint: String? = nil) {
        self.draft = draft
        self.docHint = docHint
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: AgentBarStore
    @ObservedObject var viewModel: SettingsViewModel

    private var theme: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 原生苹果风顶部居中分段导航栏
            HStack {
                Spacer()
                HStack(spacing: 3) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = (viewModel.selectedTab == tab)
                        Button {
                            viewModel.selectedTab = tab
                        } label: {
                            Text(tab.title)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                        .fill(isSelected ? theme.card : Color.clear)
                                        .shadow(color: isSelected ? theme.cardShadowColor : .clear, radius: 2, x: 0, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            HairlineDivider(color: theme.divider)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    switch viewModel.selectedTab {
                    case .providers:
                        providersTab
                    case .credentials:
                        credentialsTab
                    case .extensions:
                        extensionsTab
                    }
                }
                .padding(20)
            }

            if viewModel.selectedTab == .credentials {
                HairlineDivider(color: theme.divider)
                HStack {
                    Text("配置仅保存在本机 ~/.config/agentbar/config.json")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                    Spacer()
                    Button("保存并立即刷新") {
                        store.saveConfig()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 560, height: 520)
        .background(theme.settingsCanvas)
        .preferredColorScheme(store.config.appearanceMode.preferredColorScheme)
        .sheet(isPresented: $viewModel.isPresentingEditor) {
            if let editorVM = viewModel.editorViewModel {
                CustomProviderEditorSheet(
                    editorVM: editorVM,
                    store: store,
                    onSave: { updated in
                        if let idx = store.customProviders.firstIndex(where: { $0.id == updated.id }) {
                            store.customProviders[idx] = updated
                        } else {
                            store.customProviders.append(updated)
                        }
                        store.saveCustomProviders()
                        viewModel.closeEditor()
                    },
                    onCancel: {
                        viewModel.closeEditor()
                    }
                )
                .preferredColorScheme(store.config.appearanceMode.preferredColorScheme)
            }
        }
    }

    // MARK: - 标签一：平台管理

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            nativeGroup(title: "通用") {
                VStack(spacing: 0) {
                    nativeRow {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("外观模式")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text("默认浅色，可切换深色或跟随系统昼夜变化")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.appearanceMode },
                            set: {
                                store.config.appearanceMode = $0
                                store.saveConfig()
                            }
                        )) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 196)
                    }

                    HairlineDivider(color: theme.divider).padding(.leading, 14)

                    nativeRow {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("自动隐藏未配置平台")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text("未安装的平台不占用下拉面板空间")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.config.hideUnconfiguredProviders },
                            set: {
                                store.config.hideUnconfiguredProviders = $0
                                store.saveConfig()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HairlineDivider(color: theme.divider).padding(.leading, 14)

                    nativeRow {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("自定义平台排序")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text("开启后可拖拽下方平台调整顺序，将最常用的排到前 3 位")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.config.enableCustomOrder },
                            set: {
                                store.config.enableCustomOrder = $0
                                store.saveConfig()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HairlineDivider(color: theme.divider).padding(.leading, 14)

                    nativeRow {
                        Text("自动刷新间隔")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.config.refreshIntervalMinutes },
                            set: {
                                store.config.refreshIntervalMinutes = $0
                                store.saveConfig()
                            }
                        )) {
                            Text("每 1 分钟").tag(1)
                            Text("每 3 分钟").tag(3)
                            Text("每 5 分钟").tag(5)
                            Text("每 10 分钟").tag(10)
                        }
                        .labelsHidden()
                        .frame(width: 112)
                    }
                }
            }

            nativeGroup(title: store.config.enableCustomOrder ? "平台列表（可拖拽排序，前 3 位默认直接展示）" : "平台列表") {
                let items = store.orderedAllDescriptors
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, desc in
                        let rowView = nativeRow {
                            HStack(spacing: 9) {
                                if store.config.enableCustomOrder {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.textMuted.opacity(0.75))
                                        .frame(width: 14)
                                }

                                Circle()
                                    .fill(Color(hex: desc.accentHex))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 1.5) {
                                    HStack(spacing: 6) {
                                        Text(desc.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(theme.textPrimary)
                                        statusPill(for: desc.id)
                                        if desc.isCustom {
                                            pillTag("自定义", color: theme.actionBlue)
                                        }
                                    }
                                    Text(desc.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textMuted)
                                }
                            }
                            Spacer()

                            if store.config.enableCustomOrder {
                                HStack(spacing: 2) {
                                    Button {
                                        store.nudgeProvider(id: desc.id, direction: -1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(idx == 0 ? theme.textMuted.opacity(0.3) : theme.textSecondary)
                                            .frame(width: 20, height: 20)
                                            .background(theme.cardElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(idx == 0)

                                    Button {
                                        store.nudgeProvider(id: desc.id, direction: 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(idx == items.count - 1 ? theme.textMuted.opacity(0.3) : theme.textSecondary)
                                            .frame(width: 20, height: 20)
                                            .background(theme.cardElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(idx == items.count - 1)
                                }
                                .padding(.trailing, 4)
                            }

                            Toggle("", isOn: Binding(
                                get: {
                                    if desc.isCustom {
                                        return store.customProviders.first(where: { $0.id == desc.id })?.enabled ?? true
                                    }
                                    return store.config.isBuiltInEnabled(desc.id)
                                },
                                set: { enabled in
                                    if desc.isCustom {
                                        if let cIdx = store.customProviders.firstIndex(where: { $0.id == desc.id }) {
                                            store.customProviders[cIdx].enabled = enabled
                                            store.saveCustomProviders()
                                        }
                                    } else {
                                        store.config.setBuiltIn(desc.id, enabled: enabled)
                                        store.saveConfig()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .background(viewModel.draggingProviderID == desc.id ? theme.actionBlue.opacity(0.08) : Color.clear)

                        if store.config.enableCustomOrder {
                            rowView
                                .onDrag {
                                    viewModel.draggingProviderID = desc.id
                                    return NSItemProvider(object: desc.id as NSString)
                                }
                                .onDrop(
                                    of: [UTType.plainText],
                                    delegate: ProviderReorderDropDelegate(
                                        targetID: desc.id,
                                        viewModel: viewModel,
                                        store: store
                                    )
                                )
                        } else {
                            rowView
                        }

                        if idx < items.count - 1 {
                            HairlineDivider(color: theme.divider).padding(.leading, 32)
                        }
                    }
                }
            }

            nativeGroup(title: "Claude Code 实时采集钩子") {
                nativeRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.claudeHookInstalled ? "已开启官方 statusLine 同步" : "尚未开启实时采集钩子")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(store.claudeHookInstalled ? theme.healthColor(for: .good) : theme.textPrimary)
                        Text("零 Token 消耗读取 5 小时与周额度，不会触发 429 限流")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    if store.claudeHookInstalled {
                        Button("卸载") {
                            store.uninstallClaudeHook()
                        }
                        .controlSize(.small)
                    } else {
                        Button("一键开启") {
                            store.installClaudeHook()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusPill(for id: String) -> some View {
        if let snap = store.snapshot(for: id) {
            switch snap.status {
            case .active:
                pillTag("已同步", color: theme.healthColor(for: .good))
            case .needsSetup:
                pillTag("待接入", color: theme.healthColor(for: .warning))
            case .error:
                pillTag("异常", color: theme.healthColor(for: .critical))
            case .unavailable:
                pillTag("未检测到", color: theme.textMuted)
            }
        }
    }

    private func pillTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - 标签二：密钥与代理

    private var credentialsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            nativeGroup(title: "DeepSeek 官方余额") {
                VStack(spacing: 0) {
                    nativeFieldRow(label: "API Key", hint: "前往 platform.deepseek.com 创建") {
                        HStack(spacing: 6) {
                            SecureField("sk-...", text: $store.config.deepseekAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 196)
                            Button(viewModel.isTestingDeepSeek ? "测试中" : "测试") {
                                viewModel.isTestingDeepSeek = true
                                viewModel.deepseekTestMessage = nil
                                Task {
                                    let snap = await store.testDeepSeek()
                                    viewModel.isTestingDeepSeek = false
                                    switch snap.status {
                                    case .active:
                                        let val = snap.windows.map { $0.formattedPrimaryValue(showUsed: false) }.joined(separator: " / ")
                                        viewModel.deepseekTestIsSuccess = true
                                        viewModel.deepseekTestMessage = "连接成功，当前余额：\(val)"
                                        await store.refreshAll()
                                    case .error(let msg):
                                        viewModel.deepseekTestIsSuccess = false
                                        viewModel.deepseekTestMessage = msg
                                    case .unavailable(let reason):
                                        viewModel.deepseekTestIsSuccess = false
                                        viewModel.deepseekTestMessage = reason
                                    case .needsSetup(let hint, _):
                                        viewModel.deepseekTestIsSuccess = false
                                        viewModel.deepseekTestMessage = hint
                                    }
                                }
                            }
                            .controlSize(.small)
                            .disabled(viewModel.isTestingDeepSeek)
                        }
                    }

                    if let msg = viewModel.deepseekTestMessage {
                        HairlineDivider(color: theme.divider).padding(.leading, 14)
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.deepseekTestIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(viewModel.deepseekTestIsSuccess ? theme.healthColor(for: .good) : theme.healthColor(for: .critical))
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundStyle(viewModel.deepseekTestIsSuccess ? theme.healthColor(for: .good) : theme.errorText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    HairlineDivider(color: theme.divider).padding(.leading, 14)
                    nativeFieldRow(label: "进度条参考满额", hint: "用于绿/黄/红比例折算") {
                        TextField("50", value: $store.config.deepseekReferenceCap, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
            }

            nativeGroup(title: "Cursor 与 OpenCode") {
                VStack(spacing: 0) {
                    nativeFieldRow(label: "Cursor API Key", hint: "团队/企业版 Admin Key") {
                        SecureField("key_...", text: $store.config.cursorAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }
                    HairlineDivider(color: theme.divider).padding(.leading, 14)
                    nativeFieldRow(label: "Cursor 月度预算", hint: "单位：美元（USD）") {
                        TextField("20", value: $store.config.cursorMonthlyBudgetUSD, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    HairlineDivider(color: theme.divider).padding(.leading, 14)
                    nativeFieldRow(label: "OpenCode 命令", hint: "输出标准额度 JSON") {
                        TextField("可选命令", text: $store.config.opencodeCommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }
                }
            }

            nativeGroup(title: "网络代理") {
                nativeFieldRow(label: "代理地址", hint: "留空自动跟随 macOS 系统代理") {
                    TextField("http://127.0.0.1:7897", text: $store.config.proxyURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }
        }
    }

    // MARK: - 标签三：扩展平台与快速导入模板

    private var extensionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            nativeGroup(title: "一键快速导入模板") {
                VStack(spacing: 0) {
                    ForEach(Array(ProviderPreset.all.enumerated()), id: \.element.id) { idx, preset in
                        nativeRow {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: preset.accentHex))
                                    .frame(width: 7.5, height: 7.5)
                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(preset.name)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(theme.textPrimary)
                                    Text(preset.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textMuted)
                                }
                            }
                            Spacer()
                            Button("添加") {
                                var copy = preset.template
                                copy.id = "\(preset.template.id)-\(UUID().uuidString.prefix(4).lowercased())"
                                viewModel.startEditing(copy, docHint: preset.docHint)
                            }
                            .controlSize(.small)
                        }

                        if idx < ProviderPreset.all.count - 1 {
                            HairlineDivider(color: theme.divider).padding(.leading, 32)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("已导入的自定义平台")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .padding(.leading, 4)
                    Spacer()
                    Button("打开配置目录") {
                        ConfigStore.shared.ensureDirectories()
                        NSWorkspace.shared.open(ConfigStore.shared.baseDirectory)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.actionBlue)
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    if store.customProviders.isEmpty {
                        Text("暂未导入自定义平台，点击上方任意模板即可快速接入。")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(Array(store.customProviders.enumerated()), id: \.element.id) { idx, item in
                            nativeRow {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: item.accentHex))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Text(item.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(theme.textPrimary)
                                        Text(item.mode.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.textMuted)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    Button("编辑") {
                                        viewModel.startEditing(item)
                                    }
                                    .controlSize(.small)

                                    Button("删除", role: .destructive) {
                                        store.customProviders.removeAll { $0.id == item.id }
                                        store.saveCustomProviders()
                                    }
                                    .controlSize(.small)
                                }
                            }

                            if idx < store.customProviders.count - 1 {
                                HairlineDivider(color: theme.divider).padding(.leading, 32)
                            }
                        }
                    }
                }
                .background(theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(theme.border, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: theme.cardShadowColor, radius: 2.5, x: 0, y: 1)
            }
        }
    }

    // MARK: - 原生分组卡片容器组件

    private func nativeGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .padding(.leading, 4)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(theme.border, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: theme.cardShadowColor, radius: 2.5, x: 0, y: 1)
        }
    }

    private func nativeRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func nativeFieldRow<Control: View>(
        label: String,
        hint: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct CustomProviderEditorSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var editorVM: CustomEditorViewModel
    let store: AgentBarStore
    let onSave: (CustomProviderConfig) -> Void
    let onCancel: () -> Void

    private var theme: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("导入扩展平台")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                if let hint = editorVM.docHint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textMuted)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("平台名称")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            TextField("例如：硅基流动", text: $editorVM.draft.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("标签文字")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            TextField("例如：官方余额", text: $editorVM.draft.badge)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("采集模式")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            Picker("", selection: $editorVM.draft.mode) {
                                ForEach(CustomProviderMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("主题色")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            TextField("#38BDF8", text: $editorVM.draft.accentHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }

                    if editorVM.draft.mode == .command {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本地执行命令（标准输出返回额度 JSON）")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            TextField("例如：my-agent usage --json", text: $editorVM.draft.command)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HTTP GET 接口地址")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(theme.textSecondary)
                                TextField("https://api.example.com/v1/balance", text: $editorVM.draft.httpURL)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("鉴权请求头")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(theme.textSecondary)
                                    TextField("Authorization", text: $editorVM.draft.authHeaderName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("前缀")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(theme.textSecondary)
                                    TextField("Bearer ", text: $editorVM.draft.authHeaderPrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 88)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("密钥 / API Key")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(theme.textSecondary)
                                SecureField("粘贴你的 API Key", text: $editorVM.draft.authToken)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("JSON 提取路径")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(theme.textSecondary)
                                    TextField("例如：data.totalBalance", text: $editorVM.draft.jsonPath)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("显示名称")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(theme.textSecondary)
                                    TextField("例如：账户余额", text: $editorVM.draft.windowLabel)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            HStack(spacing: 8) {
                                Picker("数值类型", selection: $editorVM.draft.valueKind) {
                                    ForEach(CustomHTTPValueKind.allCases) { kind in
                                        Text(kind.title).tag(kind)
                                    }
                                }
                                if editorVM.draft.valueKind == .balance {
                                    TextField("币种", text: $editorVM.draft.currency)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 65)
                                    TextField("满额参考", value: $editorVM.draft.balanceCap, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                            }
                        }
                    }

                    if let testStatus = editorVM.testStatus {
                        Text(testStatus)
                            .font(.system(size: 11.5))
                            .foregroundStyle(testStatus.hasPrefix("测试成功") ? theme.healthColor(for: .good) : theme.errorText)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(theme.border, lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }

            HairlineDivider(color: theme.divider)

            HStack {
                Button(editorVM.isTesting ? "测试中…" : "立即测试采集") {
                    editorVM.isTesting = true
                    let snapshotDraft = editorVM.draft
                    Task {
                        let snap = await store.testCustomProvider(snapshotDraft)
                        editorVM.isTesting = false
                        switch snap.status {
                        case .active:
                            let summary = snap.windows
                                .map { "\($0.label)：\($0.formattedPrimaryValue(showUsed: false))" }
                                .joined(separator: "，")
                            editorVM.testStatus = "测试成功（\(summary)）"
                        case .error(let msg):
                            editorVM.testStatus = "测试失败：\(msg)"
                        case .needsSetup(let hint, _):
                            editorVM.testStatus = "需要配置：\(hint)"
                        case .unavailable(let reason):
                            editorVM.testStatus = "不可用：\(reason)"
                        }
                    }
                }
                .disabled(editorVM.isTesting)

                Spacer()

                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(editorVM.draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editorVM.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460, height: 470)
        .background(theme.settingsCanvas)
    }
}

private struct ProviderReorderDropDelegate: DropDelegate {
    let targetID: String
    let viewModel: SettingsViewModel
    let store: AgentBarStore

    func dropEntered(info: DropInfo) {
        guard let draggedID = viewModel.draggingProviderID, draggedID != targetID else { return }
        store.moveProvider(fromID: draggedID, toID: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.draggingProviderID = nil
        return true
    }
}
