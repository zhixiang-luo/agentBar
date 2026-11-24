import Foundation
import Testing
@testable import agentBar

@Test("解析 Codex 会话日志中的 5 小时与周额度")
func codexJSONLParsing() {
    let fixedNow = Date(timeIntervalSince1970: 1_763_900_000)
    let jsonl = """
    {"timestamp":"2026-11-23T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":28.5,"window_minutes":300,"resets_at":1763950000},"secondary":{"used_percent":62.0,"window_minutes":10080,"resets_at":1764300000}}}}
    """
    let parsed = CodexProvider.parseRateLimits(fromJSONL: jsonl, now: fixedNow)
    #expect(parsed != nil)
    #expect(parsed?.planType == "Pro 订阅")
    #expect(parsed?.windows.count == 2)
    #expect(parsed?.windows[0].label == "5 小时额度")
    #expect(abs((parsed?.windows[0].remainingPercent ?? 0) - 71.5) < 0.1)
    #expect(parsed?.windows[0].health == .good)
    #expect(parsed?.windows[1].label == "周额度")
    #expect(abs((parsed?.windows[1].remainingPercent ?? 0) - 38.0) < 0.1)
    #expect(parsed?.windows[1].health == .warning)
}

@Test("解析 Codex wham/usage 实时接口 JSON")
func codexWhamUsageParsing() {
    let data = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "primary_window": {
          "used_percent": 15,
          "limit_window_seconds": 18000,
          "reset_at": 1795500000
        },
        "secondary_window": {
          "used_percent": 79,
          "limit_window_seconds": 604800,
          "reset_at": 1795800000
        }
      }
    }
    """.data(using: .utf8)!
    let parsed = CodexProvider.parseWhamUsageJSON(data: data)
    #expect(parsed != nil)
    #expect(parsed?.planType == "Plus 订阅")
    #expect(parsed?.windows.count == 2)
    #expect(parsed?.windows[0].label == "5 小时额度")
    #expect(abs((parsed?.windows[0].usedPercent ?? 0) - 15.0) < 0.1)
    #expect(parsed?.windows[1].label == "周额度")
    #expect(abs((parsed?.windows[1].usedPercent ?? 0) - 79.0) < 0.1)
}

@Test("解析 Antigravity 额度 JSON（过滤 Claude/GPT，仅展示自身 5 小时与周额度）")
func antigravityJSONParsing() {
    let raw = """
    {
      "status": "SUCCESS",
      "command": {
        "name": "usage",
        "data": {
          "groups": [
            {
              "name": "Gemini Models",
              "buckets": [
                { "id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.91, "reset_time": "2026-12-01T00:50:17Z" },
                { "id": "gemini-5h", "window": "5h", "remaining_fraction": 0.65, "reset_time": "2026-11-24T05:50:17Z" }
              ]
            },
            {
              "name": "Claude and GPT models",
              "buckets": [
                { "id": "3p-weekly", "window": "weekly", "remaining_fraction": 0, "reset_time": "2026-11-26T08:04:53Z" },
                { "id": "3p-5h", "window": "5h", "disabled": true, "remaining_fraction": 1 }
              ]
            }
          ]
        }
      }
    }
    """
    let windows = AntigravityProvider.parseAgyUsageJSON(raw)
    #expect(windows?.count == 2)
    #expect(windows?[0].label == "5 小时额度")
    #expect(abs((windows?[0].remainingPercent ?? 0) - 65.0) < 0.1)
    #expect(windows?[1].label == "周额度")
    #expect(abs((windows?[1].remainingPercent ?? 0) - 91.0) < 0.1)
}

@Test("解析 Antigravity 最高档会员（无 5 小时额度，自动展示周额度与全部额度）")
func antigravityMaxTierParsing() {
    let raw = """
    {
      "status": "SUCCESS",
      "command": {
        "name": "usage",
        "data": {
          "groups": [
            {
              "name": "Gemini Models",
              "buckets": [
                { "id": "gemini-5h", "window": "5h", "disabled": true, "remaining_fraction": 1.0 },
                { "id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.82, "reset_time": "2026-12-01T00:50:17Z" },
                { "id": "gemini-all", "window": "all", "remaining_fraction": 0.74 }
              ]
            }
          ]
        }
      }
    }
    """
    let windows = AntigravityProvider.parseAgyUsageJSON(raw)
    #expect(windows?.count == 2)
    #expect(windows?[0].label == "周额度")
    #expect(abs((windows?[0].remainingPercent ?? 0) - 82.0) < 0.1)
    #expect(windows?[1].label == "全部额度")
    #expect(abs((windows?[1].remainingPercent ?? 0) - 74.0) < 0.1)
}

@Test("解析 DeepSeek 官方余额接口 JSON")
func deepSeekBalanceParsing() throws {
    let json = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "32.50",
          "granted_balance": "2.50",
          "topped_up_balance": "30.00"
        }
      ]
    }
    """.data(using: .utf8)!
    let windows = try DeepSeekProvider.parseBalanceJSON(data: json, referenceCap: 50.0)
    #expect(windows.count == 1)
    #expect(windows[0].formattedPrimaryValue(showUsed: false) == "¥32.50")
    #expect(windows[0].health == .good)
}

@Test("自定义 HTTP JSON 路径数值提取")
func jsonPathExtraction() throws {
    let data = """
    {"balance_infos": [{"currency": "CNY", "total_balance": "18.80"}]}
    """.data(using: .utf8)!
    let obj = try JSONSerialization.jsonObject(with: data)
    let value = JSONPathExtractor.extractDouble(from: obj, path: "balance_infos.0.total_balance")
    #expect(abs((value ?? 0) - 18.80) < 0.001)
}

@Test("中文重置倒计时格式化（小时/天+小时/月度剩余天数）")
func chineseResetCountdownFormatting() {
    let base = Date(timeIntervalSince1970: 1_763_900_000)

    let inThreeHours = base.addingTimeInterval(3 * 3600 + 18 * 60)
    #expect(QuotaTimeFormatter.resetDescription(for: inThreeHours, now: base) == "还剩 3 小时 18 分钟重置")

    let inTwoDaysThreeHours = base.addingTimeInterval((2 * 24 + 3) * 3600 + 10 * 60)
    #expect(QuotaTimeFormatter.resetDescription(for: inTwoDaysThreeHours, now: base, windowLabel: "周额度") == "还剩 2 天 3 小时重置")

    let inFifteenDays = base.addingTimeInterval(15 * 24 * 3600)
    #expect(QuotaTimeFormatter.resetDescription(for: inFifteenDays, now: base, windowLabel: "月度额度") == "本月还剩 15 天重置")

    let inTwentySeconds = base.addingTimeInterval(20)
    #expect(QuotaTimeFormatter.resetDescription(for: inTwentySeconds, now: base) == "即将重置")
}

@Test("旧版配置文件向后兼容解析与自定义排序")
func backwardCompatibleConfigDecoding() throws {
    let legacyJSON = """
    {"enabledBuiltInIDs":["codex"],"hideUnconfiguredProviders":true,"refreshIntervalMinutes":5,"showUsedInsteadOfRemaining":false,"proxyURL":"","deepseekAPIKey":"","deepseekReferenceCap":50,"cursorAPIKey":"","cursorMonthlyBudgetUSD":20,"opencodeCommand":""}
    """.data(using: .utf8)!
    var decoded = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)
    #expect(decoded.appearanceMode == .light)
    #expect(decoded.refreshIntervalMinutes == 5)
    #expect(decoded.enableCustomOrder == true)
    #expect(!ProviderPreset.all.isEmpty)

    decoded.providerOrder = ["deepseek", "antigravity", "codex"]
    #expect(decoded.orderIndex(for: "deepseek") < decoded.orderIndex(for: "codex"))
    decoded.enableCustomOrder = false
    #expect(decoded.orderIndex(for: "codex") < decoded.orderIndex(for: "deepseek"))
}

@Test("解析 Codex 无 5 小时限额的高级会员（周额度 + 全部额度）")
func codexMaxTierParsing() {
    let data = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": true,
        "primary_window": null,
        "secondary_window": {
          "used_percent": 30,
          "limit_window_seconds": 604800,
          "reset_at": 1795800000
        }
      },
      "credits": {
        "has_credits": false,
        "unlimited": true,
        "balance": null
      }
    }
    """.data(using: .utf8)!
    let parsed = CodexProvider.parseWhamUsageJSON(data: data)
    #expect(parsed?.windows.count == 2)
    #expect(parsed?.windows[0].label == "周额度")
    #expect(parsed?.windows[1].label == "全部额度")
}
