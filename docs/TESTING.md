# 测试说明与发布验收清单

本文档说明 `agentBar` 的自动化单元测试、命令行诊断与手工 UI 验收流程。

---

## 一、运行自动化单元测试

本项目使用 Swift 6 原生内置的 `Testing` 框架，仅需 Apple Command Line Tools 即可运行：

```bash
cd agentBar
./scripts/run-tests.sh
```

### 当前覆盖的 9 项核心测试用例（`Tests/agentBarTests/AgentBarTests.swift`）
1. **Codex 本地 JSONL 会话日志解析**：验证 5 小时与周额度窗口百分比、套餐类型映射与健康度分级。
2. **Codex `wham/usage` 实时接口解析**：验证 `primary_window`、`secondary_window`、`reset_at` 与 `plan_type`。
3. **Codex 无 5 小时限额高级会员解析**：验证 `primary_window: null` 时自动展示 `周额度` 与 `全部额度`。
4. **Antigravity 普通会员额度 JSON 解析**：验证过滤第三方 Claude/GPT 分组，仅展示自身 `5 小时额度` 与 `周额度`。
5. **Antigravity 最高档会员额度 JSON 解析**：验证 `5h` 桶被禁用时自动展示 `周额度` 与 `全部额度`。
6. **DeepSeek 官方余额接口解析**：验证币种符号、充值/赠送明细及参考满额比例。
7. **自定义 HTTP JSON 路径数值提取**：验证嵌套点路径与数组下标提取（如 `balance_infos.0.total_balance`）。
8. **中文重置倒计时格式化**：验证「即将重置」「X 小时 Y 分钟后重置」「周X HH:mm 重置」。
9. **旧版配置文件向后兼容解析与自定义排序**：验证旧配置平滑升级（默认浅色、默认开启自定义排序）及 `orderIndex` 排序切换。

---

## 二、构建与打包验证

```bash
# 1. 重新生成浅色系小猪图标（可选，build-app.sh 会自动检查）
./scripts/generate-icon.sh

# 2. 编译 Release 并打包 dist/agentBar.app + 本地 Ad-hoc 签名
./scripts/build-app.sh
```

验证打包产物：
- `dist/agentBar.app/Contents/MacOS/agentBar` 存在且可执行；
- `dist/agentBar.app/Contents/Resources/AppIcon.icns` 与 `logo.png` 存在；
- `Info.plist` 包含 `LSUIElement = true` 与 `CFBundleIconFile = AppIcon`。

---

## 三、本机真实采集诊断

```bash
./dist/agentBar.app/Contents/MacOS/agentBar --diagnose
```

核对输出中各平台状态符合预期，且输出中**不泄露任何密钥或 Token**。

---

## 四、手工 UI 验收清单

- [ ] **菜单栏极简**：顶部菜单栏只显示 1 个开口仪表盘图标，Dock 无图标。
- [ ] **浅色系小猪桌面图标**：在 Finder / 应用程序中显示浅色系小猪 + 双层进度条图标，面板内部不出现 Logo。
- [ ] **默认浅色 + 双主题切换**：默认浅色原生毛玻璃，设置页切换深色/跟随系统后立即生效且清晰可读。
- [ ] **3 卡片高度与自动滚动**：3 个平台内完整展示无滚动条；超过 3 个或展开待接入平台后自动出现滚动条，反复展开收起无顶部留白。
- [ ] **拖拽排序与开关**：在设置页开启/关闭自定义排序、拖拽或点击 `↑ / ↓`，主面板顺序实时同步。
- [ ] **DeepSeek 即时测试**：输入密钥点击「测试」立刻返回余额或清晰中文报错。
