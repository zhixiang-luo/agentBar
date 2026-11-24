# 贡献指南（面向中文社区）

欢迎为 **agentBar** 贡献代码、平台适配器、文档改进或问题反馈！

## 设计底线（提 PR 前必看）

在提交新功能前，请确认改动符合 `agentBar` 的核心克制原则：

1. **菜单栏只保留一个图标**：不要往顶部菜单栏堆砌多平台数字或文字。
2. **下拉面板只展示额度**：不加入“最近对话”、复杂账单报表或与额度无关的监控项。
3. **纯中文体验**：所有界面文案、错误提示、注释与文档均使用自然简体中文（仅保留平台专有品牌名）。
4. **亮暗双主题适配**：所有新 UI 组件必须通过 `ThemePalette` 适配浅色与深色模式，禁止硬编码单一黑底或白底。
5. **零 Xcode 强依赖**：由于不少贡献者仅安装了 Apple Command Line Tools，视图中请优先使用 `ObservableObject` / `@ObservedObject` / `@Published`，避免依赖需要完整 Xcode 的 `@State` 宏插件。
6. **不探测未公开宿主进程**：新平台采集必须使用官方公开 API、官方 CLI 参数、官方 Hook 或用户显式配置，不硬扫宿主客户端内部未公开端口。

---

## 如何新增一个内置平台适配器？

得益于插件化 `QuotaProvider` 协议，新增一个原生平台只需 3 步：

1. 在 `Sources/agentBar/Providers/` 下新建 `<Platform>Provider.swift`，实现 `QuotaProvider` 协议：
   ```swift
   struct MyAgentProvider: QuotaProvider {
       let descriptor: ProviderDescriptor
       func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
           // 返回 .active / .needsSetup / .unavailable / .error
       }
   }
   ```
2. 在 `Sources/agentBar/Providers/QuotaProvider.swift` 的 `ProviderRegistry.builtInDescriptors` 和 `activeProviders(...)` 中注册。
3. 在 `Tests/agentBarTests/AgentBarTests.swift` 中为你的解析逻辑补充单元测试，并确认 `swift test` 与 `./scripts/build-app.sh` 全部通过。

---

## 提交规范

推荐使用简洁中文提交信息，例如：

- `新增：支持 Kimi Code 5 小时额度解析`
- `修复：Codex 代理超时时的离线日志降级提示`
- `优化：浅色模式下警告状态进度条对比度`
- `文档：补充硅基流动余额接入示例`
