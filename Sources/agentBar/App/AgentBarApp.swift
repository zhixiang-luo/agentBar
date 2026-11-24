import AppKit
import SwiftUI

@main
enum AgentBarLauncher {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Task.detached {
                await runDiagnostics()
                fflush(stdout)
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        AgentBarApp.main()
    }

    private static func runDiagnostics() async {
        let store = ConfigStore.shared
        let config = store.loadConfig()
        let custom = store.loadCustomProviders()
        let providers = ProviderRegistry.activeProviders(config: config, customConfigs: custom)
        let context = ProviderContext(config: config, store: store)

        print("== agentBar 本机诊断报告 ==")
        print("外观主题：\(config.appearanceMode.title)")
        print("自动隐藏未配置平台：\(config.hideUnconfiguredProviders ? "开启" : "关闭")")
        print("代理配置：\(config.proxyURL.isEmpty ? "跟随系统默认代理" : config.proxyURL)")
        print("")

        for provider in providers {
            let snap = await provider.fetch(context: context)
            switch snap.status {
            case .active:
                let items = snap.windows.map { win -> String in
                    let val = win.formattedPrimaryValue(showUsed: false)
                    let reset = QuotaTimeFormatter.resetDescription(for: win.resetsAt) ?? "无重置时间"
                    return "\(win.label)=\(val)（\(reset)）"
                }.joined(separator: " | ")
                print("[已同步] \(snap.name)（\(snap.badge) · \(snap.sourceLabel)）：\(items)")
            case .needsSetup(let hint, _):
                print("[待接入] \(snap.name)（\(snap.badge)）：\(hint)")
            case .unavailable(let reason):
                print("[未安装] \(snap.name)：\(reason)")
            case .error(let msg):
                print("[异常]   \(snap.name)：\(msg)")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅常驻顶部菜单栏，不占用程序坞（Dock）图标
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = ConfigStore.shared.loadConfig().appearanceMode.nsAppearance
    }
}

struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AgentBarStore()
    private let menuBarIcon = MenuBarIconFactory.makeGaugeTemplateImage()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(store: store)
                .preferredColorScheme(store.config.appearanceMode.preferredColorScheme)
        } label: {
            // 使用原型同款极简开口仪表盘 Template 图标
            Image(nsImage: menuBarIcon)
                .accessibilityLabel("agentBar")
        }
        .menuBarExtraStyle(.window)
    }
}
