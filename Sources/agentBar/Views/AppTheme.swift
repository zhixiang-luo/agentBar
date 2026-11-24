import AppKit
import SwiftUI

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// 精确还原原型质感的 macOS 原生亮/暗调色板
struct ThemePalette {
    let isDark: Bool

    init(colorScheme: ColorScheme, appearanceMode: AppAppearanceMode = .system) {
        switch appearanceMode {
        case .light:
            self.isDark = false
        case .dark:
            self.isDark = true
        case .system:
            self.isDark = (colorScheme == .dark)
        }
    }

    /// 面板底色（与 NSVisualEffectView 配合，浅色通透亮白，深色沉静通透）
    var canvasTint: Color {
        isDark ? Color(hex: "#1C1F26").opacity(0.76) : Color(hex: "#F5F6FA").opacity(0.84)
    }

    /// 设置窗口纯色底板（类似 macOS 系统设置）
    var settingsCanvas: Color {
        isDark ? Color(hex: "#1B1E24") : Color(hex: "#F4F5F8")
    }

    /// 卡片表面（浅色纯白高通透，深色柔和微亮玻璃层）
    var card: Color {
        isDark ? Color.white.opacity(0.065) : Color.white.opacity(0.95)
    }

    /// 次级胶囊 / 按钮底色
    var cardElevated: Color {
        isDark ? Color.white.opacity(0.09) : Color(hex: "#0F172A").opacity(0.055)
    }

    /// 极细外边框
    var border: Color {
        isDark ? Color.white.opacity(0.09) : Color(hex: "#0F172A").opacity(0.075)
    }

    /// 0.5pt 发丝分隔线
    var divider: Color {
        isDark ? Color.white.opacity(0.085) : Color(hex: "#0F172A").opacity(0.075)
    }

    /// 进度条背景轨道
    var track: Color {
        isDark ? Color.white.opacity(0.11) : Color(hex: "#0F172A").opacity(0.085)
    }

    var textPrimary: Color {
        isDark ? Color(hex: "#F3F4F6") : Color(hex: "#111827")
    }

    var textSecondary: Color {
        isDark ? Color(hex: "#CBD5E1") : Color(hex: "#4B5563")
    }

    var textMuted: Color {
        isDark ? Color(hex: "#8E99A8") : Color(hex: "#6B7280")
    }

    var actionBlue: Color {
        isDark ? Color(hex: "#60A5FA") : Color(hex: "#007AFF")
    }

    var cardShadowColor: Color {
        isDark ? Color.black.opacity(0.18) : Color(hex: "#0F172A").opacity(0.055)
    }

    func healthColor(for health: QuotaHealth) -> Color {
        switch health {
        case .good:
            return isDark ? Color(hex: "#34D399") : Color(hex: "#16A34A")
        case .warning:
            return isDark ? Color(hex: "#FBBF24") : Color(hex: "#D97706")
        case .critical:
            return isDark ? Color(hex: "#F87171") : Color(hex: "#DC2626")
        case .neutral:
            return Color(hex: "#6B7280")
        }
    }

    var bannerBackground: Color {
        isDark ? Color(hex: "#142B20") : Color(hex: "#ECFDF5")
    }

    var bannerBorder: Color {
        isDark ? Color(hex: "#34D399").opacity(0.32) : Color(hex: "#16A34A").opacity(0.24)
    }

    var errorText: Color {
        isDark ? Color(hex: "#FCA5A5") : Color(hex: "#B91C1C")
    }
}

/// 真正的 macOS 原生毛玻璃背景桥接（NSVisualEffectView），同步外观主题与顶部锚定回缩
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let appearanceMode: AppAppearanceMode
    let targetWindowHeight: CGFloat?

    init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        appearanceMode: AppAppearanceMode = .system,
        targetWindowHeight: CGFloat? = nil
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.appearanceMode = appearanceMode
        self.targetWindowHeight = targetWindowHeight
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.appearance = appearanceMode.nsAppearance
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearanceMode.nsAppearance
        nsView.state = .active

        if let window = nsView.window {
            window.appearance = appearanceMode.nsAppearance
            if let targetHeight = targetWindowHeight, targetHeight > 80 {
                let currentFrame = window.frame
                let delta = targetHeight - currentFrame.height
                if abs(delta) > 1.5 {
                    let newFrame = NSRect(
                        x: currentFrame.origin.x,
                        y: currentFrame.maxY - targetHeight,
                        width: currentFrame.width,
                        height: targetHeight
                    )
                    DispatchQueue.main.async {
                        window.setFrame(newFrame, display: true, animate: false)
                    }
                }
            }
        }
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

/// 0.5pt 发丝分隔线
struct HairlineDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
    }
}

/// 原型同款极简开口仪表盘矢量图标（用于菜单栏和下拉顶栏）
struct MinimalGaugeIcon: View {
    let size: CGFloat
    let lineWidth: CGFloat

    init(size: CGFloat = 14, lineWidth: CGFloat = 1.8) {
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height * 0.54
            let radius = s * 0.42

            // 开口圆弧（210° -> -30°，对应原型 <path d="M3.34 19a10 10 0 1 1 17.32 0"/>）
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: radius,
                startAngle: .degrees(150),
                endAngle: .degrees(30),
                clockwise: false
            )
            ctx.stroke(
                arc,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // 指向右上 45° 的仪表指针（对应原型 <path d="M12 14l4-4"/>）
            var needle = Path()
            needle.move(to: CGPoint(x: cx, y: cy + s * 0.04))
            needle.addLine(to: CGPoint(x: cx + radius * 0.56, y: cy - radius * 0.52))
            ctx.stroke(
                needle,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

/// 生成 macOS 顶部菜单栏专用的高分 Template NSImage（自动适配浅/深菜单栏）
enum MenuBarIconFactory {
    static func makeGaugeTemplateImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.setStroke()

            let cx = rect.midX
            let cy = rect.midY - 0.6
            let radius: CGFloat = 6.9

            // 开口圆弧（macOS 非翻转坐标：0° 在右，90° 在上，210° 在左下，330° 在右下）
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: cx, y: cy),
                radius: radius,
                startAngle: -30,
                endAngle: 210,
                clockwise: false
            )
            arc.lineWidth = 1.75
            arc.lineCapStyle = .round
            arc.stroke()

            // 右上指针
            let needle = NSBezierPath()
            needle.move(to: NSPoint(x: cx, y: cy - 0.5))
            needle.line(to: NSPoint(x: cx + 3.6, y: cy + 3.4))
            needle.lineWidth = 1.75
            needle.lineCapStyle = .round
            needle.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
