import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var viewModel: SettingsViewModel?

    func open(store: AgentBarStore, initialTab: SettingsTab = .providers) {
        if let existing = window, let viewModel {
            viewModel.selectedTab = initialTab
            applyAppearance(store.config.appearanceMode)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = SettingsViewModel(selectedTab: initialTab)
        self.viewModel = vm

        let rootView = SettingsView(store: store, viewModel: vm)
        let hosting = NSHostingController(rootView: rootView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "agentBar 设置"
        newWindow.titlebarAppearsTransparent = true
        newWindow.appearance = store.config.appearanceMode.nsAppearance
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.contentViewController = hosting

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyAppearance(_ mode: AppAppearanceMode) {
        window?.appearance = mode.nsAppearance
    }
}
