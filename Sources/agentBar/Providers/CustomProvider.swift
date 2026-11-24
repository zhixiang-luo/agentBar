import Foundation

/// 可视化/配置文件扩展平台引擎：支持本地命令模式 & HTTP JSON 接口模式
struct CustomProvider: QuotaProvider {
    let customConfig: CustomProviderConfig

    var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: customConfig.id,
            name: customConfig.name,
            subtitle: customConfig.badge,
            accentHex: customConfig.accentHex,
            symbolName: customConfig.mode == .command ? "terminal" : "globe",
            isCustom: true
        )
    }

    init(config: CustomProviderConfig) {
        self.customConfig = config
    }

    func fetch(context: ProviderContext) async -> AgentQuotaSnapshot {
        switch customConfig.mode {
        case .command:
            return await fetchFromCommand()
        case .httpJSON:
            return await fetchFromHTTP(proxyURL: context.config.proxyURL)
        }
    }

    private func fetchFromCommand() async -> AgentQuotaSnapshot {
        let now = Date()
        let cmd = customConfig.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return errorSnapshot("尚未配置采集命令", now: now)
        }

        let result = await ShellRunner.runShell(cmd, timeout: 8.0)
        guard result.exitCode == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return errorSnapshot(reason.isEmpty ? "命令退出码 \(result.exitCode)" : reason, now: now)
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StandardQuotaPayload.self, from: data) else {
            return errorSnapshot("命令输出不是有效的标准额度 JSON", now: now)
        }

        let windows = payload.windows.enumerated().compactMap { $0.element.toQuotaWindow(index: $0.offset) }
        guard !windows.isEmpty else {
            return errorSnapshot("返回 JSON 中没有有效的额度窗口", now: now)
        }

        return AgentQuotaSnapshot(
            id: descriptor.id,
            name: customConfig.name,
            badge: payload.subtitle ?? customConfig.badge,
            accentHex: customConfig.accentHex,
            symbolName: descriptor.symbolName,
            status: .active,
            windows: windows,
            sourceLabel: "自定义命令同步",
            updatedAt: now,
            isInstalled: true
        )
    }

    private func fetchFromHTTP(proxyURL: String) async -> AgentQuotaSnapshot {
        let now = Date()
        let urlStr = customConfig.httpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlStr) else {
            return errorSnapshot("接口地址格式无效", now: now)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let headerName = customConfig.authHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = customConfig.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !headerName.isEmpty && !token.isEmpty {
            request.setValue("\(customConfig.authHeaderPrefix)\(token)", forHTTPHeaderField: headerName)
        }

        do {
            let session = HTTPClient.makeSession(proxyURL: proxyURL)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return errorSnapshot("接口返回 HTTP \(code)", now: now)
            }

            let json = try JSONSerialization.jsonObject(with: data)
            guard let numericValue = JSONPathExtractor.extractDouble(from: json, path: customConfig.jsonPath) else {
                return errorSnapshot("未能在路径「\(customConfig.jsonPath)」提取到数值", now: now)
            }

            let kind: QuotaWindowKind
            switch customConfig.valueKind {
            case .balance:
                kind = .balance(
                    amount: numericValue,
                    currency: customConfig.currency.isEmpty ? "CNY" : customConfig.currency,
                    referenceCap: max(customConfig.balanceCap, 1.0)
                )
            case .usedPercent:
                kind = .percentage(usedPercent: numericValue)
            case .remainingPercent:
                kind = .percentage(usedPercent: max(0, min(100, 100.0 - numericValue)))
            }

            let window = QuotaWindow(
                id: "\(descriptor.id)-http",
                label: customConfig.windowLabel.isEmpty ? "当前额度" : customConfig.windowLabel,
                kind: kind,
                resetsAt: nil
            )

            return AgentQuotaSnapshot(
                id: descriptor.id,
                name: customConfig.name,
                badge: customConfig.badge,
                accentHex: customConfig.accentHex,
                symbolName: descriptor.symbolName,
                status: .active,
                windows: [window],
                sourceLabel: "自定义接口同步",
                updatedAt: now,
                isInstalled: true
            )
        } catch {
            return errorSnapshot("请求失败：\(error.localizedDescription)", now: now)
        }
    }

    private func errorSnapshot(_ message: String, now: Date) -> AgentQuotaSnapshot {
        AgentQuotaSnapshot(
            id: descriptor.id,
            name: customConfig.name,
            badge: "采集异常",
            accentHex: customConfig.accentHex,
            symbolName: descriptor.symbolName,
            status: .error(message: message),
            windows: [],
            sourceLabel: "扩展平台",
            updatedAt: now,
            isInstalled: true
        )
    }
}
