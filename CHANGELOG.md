# 更新日志

本文件记录 `agentBar` 每个版本的主要变更。

## [0.2.0] - 2026-11-24

### 新增
- **浅色系小猪 App 图标**：延续小猪工具家族圆耳奶白风格，暖白浅粉底板 + 白玉双层进度条，打包为完整多分辨率 `AppIcon.icns`（仅用于桌面安装包图标，界面内部保持克制）。
- **macOS 原生毛玻璃亮 / 暗双主题**：采用 `NSVisualEffectView` + `0.5pt` 发丝分隔线 + 默认浅色模式，支持在「设置 → 平台管理」切换浅色 / 深色 / 跟随系统。
- **极简开口仪表盘图标**：高分 Template 矢量图标同时用于顶部菜单栏与下拉顶栏，顶栏仅保留更新时间、刷新与设置。
- **默认展示 3 张卡片 + 自动滚动**：可视内容区上限调整为 `520pt`，1～3 个平台完整一屏展示，超出自动出现滚动条，并修复展开/收起后顶部留白问题。
- **自定义平台排序与拖拽**：设置页新增「自定义平台排序」总开关，支持按住 `≡` 手柄拖拽排序与 `↑ / ↓` 微调，将最常看的平台排到前 3 位。
- **Codex 实时同步 & 三平台最高档会员自适应**：Codex 接入本机 `~/.codex/auth.json` 实时接口；Antigravity 自动过滤第三方 Claude/GPT 分组并适配真实 `agy` CLI 结构；Codex / Claude Code / Antigravity 均支持无 5 小时限额会员自动展示周额度 + 全部额度。
- **DeepSeek 即时测试与国内一键预设库**：设置页新增 DeepSeek 「测试」按钮与固定保存底栏；内置硅基流动、Kimi、OpenRouter、自定义 CLI/OpenCode、通用 HTTP/中转站 5 套一键导入模板。
- **命令行诊断与全套中文开源文档**：新增 `agentBar --diagnose`、`./scripts/run-tests.sh`、高清双主题预览图 `assets/ui-preview.png` 及离线交互原型 `docs/prototype.html`。

## [0.1.0] - 2026-11-23

### 新增
- 首个可编译打包的 macOS 原生 SwiftUI 菜单栏版本（零第三方依赖）。
- 支持单图标菜单栏、纯中文卡片与 5 小时/周额度中文重置倒计时。
- 内置 Claude Code、Codex、Antigravity、Cursor、DeepSeek、OpenCode 6 个基础采集器及自定义扩展引擎。
