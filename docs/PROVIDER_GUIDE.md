# 平台接入与自定义扩展手册

本文档面向希望快速导入自己常用 AI Agent 的开发者，涵盖所有内置平台与自定义扩展方式。

---

## 一、内置平台快速接入

### 1. Codex（自动读取）
- **前提**：已在本机登录过 Codex（存在 `~/.codex/auth.json` 或 `~/.codex/sessions/`）。
- **同步机制**：
  1. 优先读取 `~/.codex/auth.json` 实时拉取最新的 5 小时额度与周额度；
  2. 若网络离线或接口异常，自动极速读取 `~/.codex/sessions/**/*.jsonl` 尾部最新记录（大文件仅读尾段，毫秒级响应）；
  3. 若开通的是无 5 小时限额的高级会员，自动展示 **周额度** 与 **全部额度 / Credits**。
- **代理提示**：默认自动跟随 macOS 系统代理（如 Clash Verge 开启「系统代理」）；若未开系统代理，可在「设置 → 密钥与代理」填写代理地址（如 `http://127.0.0.1:7897`）。

### 2. Antigravity（反重力）
- **方式 A（推荐，官方 CLI）**：
  ```bash
  brew install --cask antigravity-cli
  agy
  ```
  安装后直接刷新即可自动同步。`agentBar` 会自动过滤掉第三方 Claude / GPT 分组，只干净展示反重力自身的 **5 小时额度** 和 **周额度**（无 5 小时限额的高级会员自动展示 **周额度** 与 **全部额度**）。
- **方式 B（本地缓存推送）**：
  外部脚本按下方标准 JSON 格式写入 `~/.config/agentbar/cache/antigravity.json` 即可自动读取。

### 3. Claude Code（一键开启，零 API 消耗）
- 在面板或「设置 → 平台管理」点击 **「一键开启」**；
- `agentBar` 会在 `~/.claude/settings.json` 中安全挂接官方 `statusLine` 采集脚本（保留用户原有状态栏脚本并链式透传）；
- 下次在 Claude Code 对话后自动写入 `~/.config/agentbar/cache/claude-code.json` 实时显示 5 小时与周额度（无 5 小时限额时展示周额度与全部额度），零 Token 消耗、不触发 429。

### 4. DeepSeek
- 前往 [DeepSeek 开放平台](https://platform.deepseek.com) 获取 API Key；
- 打开「设置 → 密钥与代理」，粘贴到 **DeepSeek API Key**，直接点击输入框旁的 **「测试」** 按钮即可当场查看余额或中文报错原因；
- 确认无误后点击底部固定按钮 **「保存并立即刷新」**，卡片即会出现在主面板。

### 5. Cursor / OpenCode
- **Cursor**：团队/企业版可在「设置 → 密钥与代理」填入 Cursor Admin API Key 及月度预算；
- **OpenCode**：可在「设置 → 密钥与代理」填入输出标准 JSON 的本机命令，或直接写入 `~/.config/agentbar/cache/opencode.json`。

---

## 二、自定义排序（把最常用的 3 个排最前面）

1. 打开「设置 → 平台管理」，确认 **「自定义平台排序」** 开关为开启状态；
2. 在「平台列表」中按住左侧 `≡` 拖拽手柄上下拖动，或点击右侧 `↑ / ↓` 按钮微调；
3. 主面板默认一屏完整展示前 3 个平台，超过 3 个自动出现滚动条。

---

## 三、10 秒导入新平台（无需改代码）

点击主面板底栏 **「+ 导入平台」**（或「设置 → 扩展平台」），直接选用内置一键模板：

1. **硅基流动（SiliconFlow）**：`https://api.siliconflow.cn/v1/user/info` → 路径 `data.totalBalance`
2. **Kimi / Moonshot**：`https://api.moonshot.cn/v1/users/me/balance` → 路径 `data.available_balance`
3. **OpenRouter**：`https://openrouter.ai/api/v1/credits` → 路径 `data.total_credits`
4. **自定义 CLI / OpenCode 插件**：任意可执行命令或脚本
5. **通用 HTTP 接口 / 中转站（OneAPI / NewAPI）**：任意返回 JSON 的 GET 接口

每次填写后均可先点 **「立即测试采集」** 确认返回数值正确再保存。

---

## 四、标准 JSON 交换协议（命令模式 & 本地缓存通用）

```json
{
  "subtitle": "订阅额度",
  "updatedAt": 1763950000,
  "windows": [
    {
      "label": "5 小时额度",
      "usedPercent": 24.5,
      "resetsAt": 1763968000
    },
    {
      "label": "周额度",
      "remainingPercent": 62.0,
      "resetsAtISO": "2026-11-28T08:00:00Z"
    }
  ]
}
```

余额型窗口格式：

```json
{
  "subtitle": "API 余额",
  "windows": [
    {
      "label": "账户余额",
      "balance": 42.5,
      "currency": "CNY",
      "referenceCap": 100.0,
      "detail": "充值 ¥40.00 · 赠送 ¥2.50"
    }
  ]
}
```

所有自定义平台均保存在本机 `~/.config/agentbar/providers.json`，支持手动编辑、备份与分享。
