# agentBar 架构与扩展规范

## 1. 分层架构

1. **Models（统一数据模型）**
   - `AgentQuotaSnapshot`: 统一表示任意平台的额度快照（平台 ID、中文名、标签、主题色、状态、额度窗口列表、来源说明、更新时间）。
   - `QuotaWindow`: 单个额度维度，支持两种呈现模式：
     - **百分比周期模式**（`percentage`）：如「5 小时额度」「周额度」「全部额度」，展示剩余或已用百分比、6pt 进度条颜色（>50% 绿、20–50% 黄、≤20% 红）与精准中文重置倒计时。
     - **余额模式**（`balance`）：如 DeepSeek / 硅基流动 / Kimi 账户余额，展示币种金额以及按参考满额折算的健康进度条。
   - `AppConfig` & `ProviderPreset`: 持久化外观主题（默认浅色）、自定义排序开关与顺序数组（`enableCustomOrder` / `providerOrder`）、代理地址、平台密钥与国内一键预设模板库。
2. **Providers（插件化采集协议）**
   - 所有内置与自定义扩展平台均实现 `QuotaProvider` 协议，通过 `ProviderRegistry` 统一按用户排序调度。
   - 新增原生内置平台只需在 `Sources/agentBar/Providers/` 新增 1 个 Swift 文件并在 `ProviderRegistry` 注册。
3. **Services（基础设施）**
   - `ConfigStore`: 读写 `~/.config/agentbar/config.json`、`providers.json` 与 `cache/`。
   - `ClaudeHookInstaller`: 一键为 `~/.claude/settings.json` 安装/卸载官方 `statusLine` 采集脚本（保留用户原有脚本并链式透传，零 Token 消耗、不触发 429）。
   - `HTTPClient` & `ShellRunner`: 使用 `URLSessionConfiguration.default` 自动继承 macOS 系统代理与环境变量代理，并支持自定义代理地址。
4. **Views（macOS 原生毛玻璃纯中文界面）**
   - `AppTheme`: 定义亮/暗调色板、`NSVisualEffectView` 毛玻璃桥接（含顶部锚定窗口缩放防止展开收起留白）、`0.5pt` 发丝分隔线与极简开口仪表盘 Template 图标。
   - `MenuBarPopoverView`: `332pt` 宽极简弹窗，默认一屏展示 3 张卡片（`maxBodyHeight = 520pt`），超出自动出现滚动条，待接入平台默认折叠收纳。
   - `SettingsView`: 仿 macOS「系统设置」三标签窗口（「平台管理」「密钥与代理」「扩展平台」），支持拖拽排序、DeepSeek 实时测试与自定义扩展平台测试。

## 2. 各内置平台数据源与高级会员适配

| 平台 | 数据采集方式 | 最高档会员（无 5h 限额）适配 |
| :--- | :--- | :--- |
| **Codex** | 优先读取 `~/.codex/auth.json` 实时拉取 `wham/usage`；离线降级扫描 `~/.codex/sessions/**/*.jsonl` 尾部 `rate_limits` | `primary_window` 为空时自动展示 `周额度` + `additional_rate_limits` / `credits`（全部额度） |
| **Antigravity（反重力）** | 优先读取 `~/.config/agentbar/cache/antigravity.json`，否则调用官方 `agy --print /usage --output-format json` 并过滤第三方 Claude/GPT 组 | `5h` 桶缺失或 `disabled: true` 时自动展示 `周额度` + 其余有效桶（全部/月度额度） |
| **Claude Code** | 官方 `statusLine` 钩子实时写入 `~/.config/agentbar/cache/claude-code.json` | 无 `five_hour` 时自动采集并展示 `seven_day`（周额度）与 `all`/`total`/`monthly`（全部额度） |
| **DeepSeek** | 调用官方余额接口 `GET https://api.deepseek.com/user/balance`，兼容字符串/数值字段与空余额 | 展示账户可用余额 + 充值/赠送明细 |
| **Cursor** | 调用官方 Admin Spend API 或本地缓存 | 展示本月预算使用进度 |
| **OpenCode** | 支持自定义命令输出标准 JSON 或本地缓存 | 按输出窗口自动渲染 |
