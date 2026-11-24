import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: render-preview.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let width: CGFloat = 1600
let height: CGFloat = 940

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to get CGContext\n", stderr)
    exit(1)
}

// 切换为左上角坐标系，方便精准排版
ctx.translateBy(x: 0, y: height)
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.setShouldSmoothFonts(true)

let cs = CGColorSpaceCreateDeviceRGB()

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: alpha)
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(color.cgColor)
    ctx.fillPath()
}

func strokeRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, width: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.strokePath()
}

func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, rightAlign: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let drawX = rightAlign ? (point.x - size.width) : point.x
    // 在翻转坐标系中用 NSAttributedString 绘制时，局部还原 Y 轴保证文字正向清晰
    ctx.saveGState()
    ctx.translateBy(x: drawX, y: point.y + size.height)
    ctx.scaleBy(x: 1, y: -1)
    str.draw(at: .zero)
    ctx.restoreGState()
}

func drawMinimalGauge(center: CGPoint, radius: CGFloat, color: NSColor, lineWidth: CGFloat = 2.0) {
    ctx.saveGState()
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    // 左上角坐标系下：150° 为左下，30° 为右下，clockwise: false 为经顶部画大弧
    ctx.addArc(center: center, radius: radius, startAngle: .pi * 150 / 180, endAngle: .pi * 30 / 180, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: center.x, y: center.y + radius * 0.1))
    ctx.addLine(to: CGPoint(x: center.x + radius * 0.56, y: center.y - radius * 0.52))
    ctx.strokePath()
    ctx.restoreGState()
}

// 整体底板
fillRoundedRect(CGRect(x: 0, y: 0, width: width, height: height), radius: 0, color: rgba(0xF8FAFC))

struct SampleWindow {
    let label: String
    let valueText: String
    let progress: CGFloat
    let colorHex: UInt32
    let resetText: String
}

struct SampleCard {
    let name: String
    let badge: String
    let dotHex: UInt32
    let windows: [SampleWindow]
}

func drawPanelShowcase(originX: CGFloat, isDark: Bool) {
    let panelRect = CGRect(x: originX, y: 28, width: 756, height: 884)
    let panelPath = CGPath(roundedRect: panelRect, cornerWidth: 28, cornerHeight: 28, transform: nil)

    // 渐变壁纸背景
    ctx.saveGState()
    ctx.addPath(panelPath)
    ctx.clip()
    let bgColors: [CGColor] = isDark
        ? [rgba(0x0F172A).cgColor, rgba(0x1E1B4B).cgColor, rgba(0x172554).cgColor]
        : [rgba(0xDCEAFE).cgColor, rgba(0xFCE7F3).cgColor, rgba(0xFEF3C7).cgColor]
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: panelRect.minX, y: panelRect.minY),
            end: CGPoint(x: panelRect.maxX, y: panelRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()
    strokeRoundedRect(panelRect, radius: 28, color: isDark ? rgba(0xFFFFFF, 0.12) : rgba(0x0F172A, 0.08), width: 1.5)

    // 左上角模式胶囊标签
    let badgeRect = CGRect(x: originX + 34, y: 58, width: isDark ? 210 : 230, height: 34)
    fillRoundedRect(badgeRect, radius: 17, color: isDark ? rgba(0xFFFFFF, 0.12) : rgba(0xFFFFFF, 0.80))
    drawText(
        isDark ? "深色模式 · 夜间护眼" : "浅色模式 · 默认原生质感",
        at: CGPoint(x: badgeRect.minX + 16, y: badgeRect.minY + 7),
        font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        color: isDark ? rgba(0xE2E8F0) : rgba(0x334155)
    )

    // 右上角模拟 macOS 菜单栏单图标
    let barRect = CGRect(x: panelRect.maxX - 186, y: 58, width: 152, height: 34)
    fillRoundedRect(barRect, radius: 17, color: isDark ? rgba(0x000000, 0.45) : rgba(0xFFFFFF, 0.80))
    strokeRoundedRect(barRect, radius: 17, color: isDark ? rgba(0xFFFFFF, 0.12) : rgba(0x0F172A, 0.06), width: 1)
    let iconPill = CGRect(x: barRect.minX + 16, y: barRect.minY + 5, width: 34, height: 24)
    fillRoundedRect(iconPill, radius: 6, color: isDark ? rgba(0xFFFFFF, 0.16) : rgba(0x0F172A, 0.08))
    drawMinimalGauge(
        center: CGPoint(x: iconPill.midX, y: iconPill.midY + 1),
        radius: 7.5,
        color: isDark ? rgba(0xF8FAFC) : rgba(0x111827),
        lineWidth: 2.0
    )
    drawText(
        isDark ? "22:30" : "10:45",
        at: CGPoint(x: barRect.maxX - 18, y: barRect.minY + 7),
        font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
        color: isDark ? rgba(0xF1F5F9) : rgba(0x1E293B),
        rightAlign: true
    )

    // 中央弹窗主体（约 1.5x 放大渲染保证高清锐利）
    let popW: CGFloat = 500
    let popH: CGFloat = 736
    let popX = panelRect.midX - popW / 2
    let popY: CGFloat = 122
    let popRect = CGRect(x: popX, y: popY, width: popW, height: popH)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 48, color: rgba(0x000000, isDark ? 0.55 : 0.16).cgColor)
    fillRoundedRect(popRect, radius: 22, color: isDark ? rgba(0x1C1F26, 0.94) : rgba(0xF6F7FA, 0.94))
    ctx.restoreGState()
    strokeRoundedRect(popRect, radius: 22, color: isDark ? rgba(0xFFFFFF, 0.12) : rgba(0x0F172A, 0.09), width: 1.5)

    let textPrimary = isDark ? rgba(0xF3F4F6) : rgba(0x111827)
    let textSecondary = isDark ? rgba(0xCBD5E1) : rgba(0x4B5563)
    let textMuted = isDark ? rgba(0x8E99A8) : rgba(0x6B7280)
    let dividerColor = isDark ? rgba(0xFFFFFF, 0.09) : rgba(0x0F172A, 0.08)
    let cardBg = isDark ? rgba(0xFFFFFF, 0.065) : rgba(0xFFFFFF, 0.96)
    let cardBorder = isDark ? rgba(0xFFFFFF, 0.09) : rgba(0x0F172A, 0.07)
    let pillBg = isDark ? rgba(0xFFFFFF, 0.09) : rgba(0x0F172A, 0.055)
    let trackBg = isDark ? rgba(0xFFFFFF, 0.11) : rgba(0x0F172A, 0.085)

    // 顶栏（极简开口仪表图标 + agentBar + 更新时间 + 刷新 + 设置）
    drawMinimalGauge(center: CGPoint(x: popX + 34, y: popY + 32), radius: 9.5, color: textPrimary.withAlphaComponent(0.85), lineWidth: 2.2)
    drawText("agentBar", at: CGPoint(x: popX + 54, y: popY + 19), font: NSFont.systemFont(ofSize: 19, weight: .semibold), color: textPrimary)
    drawText("刚刚更新", at: CGPoint(x: popRect.maxX - 96, y: popY + 22), font: NSFont.systemFont(ofSize: 15, weight: .regular), color: textMuted, rightAlign: true)

    let refreshBtn = CGRect(x: popRect.maxX - 84, y: popY + 15, width: 32, height: 32)
    let settingsBtn = CGRect(x: popRect.maxX - 44, y: popY + 15, width: 32, height: 32)
    fillRoundedRect(refreshBtn, radius: 8, color: pillBg)
    fillRoundedRect(settingsBtn, radius: 8, color: pillBg)
    drawText("↻", at: CGPoint(x: refreshBtn.minX + 9, y: refreshBtn.minY + 4), font: NSFont.systemFont(ofSize: 18, weight: .medium), color: textSecondary)
    drawText("⚙", at: CGPoint(x: settingsBtn.minX + 7, y: settingsBtn.minY + 4), font: NSFont.systemFont(ofSize: 18, weight: .medium), color: textSecondary)

    // 顶部分隔线
    fillRoundedRect(CGRect(x: popX, y: popY + 62, width: popW, height: 1), radius: 0, color: dividerColor)

    let greenHex: UInt32 = isDark ? 0x34D399 : 0x16A34A
    let amberHex: UInt32 = isDark ? 0xFBBF24 : 0xD97706
    let redHex: UInt32 = isDark ? 0xF87171 : 0xDC2626

    let cards: [SampleCard] = [
        SampleCard(
            name: "Codex",
            badge: "Plus 订阅",
            dotHex: 0x10A37F,
            windows: [
                SampleWindow(label: "5 小时额度", valueText: "剩余 95%", progress: 0.95, colorHex: greenHex, resetText: "还剩 1 小时 57 分钟重置"),
                SampleWindow(label: "周额度", valueText: "剩余 20%", progress: 0.20, colorHex: redHex, resetText: "还剩 1 天 9 小时重置")
            ]
        ),
        SampleCard(
            name: "Antigravity（反重力）",
            badge: "官方 CLI",
            dotHex: 0x3B82F6,
            windows: [
                SampleWindow(label: "5 小时额度", valueText: "剩余 61%", progress: 0.61, colorHex: greenHex, resetText: "还剩 3 小时 4 分钟重置"),
                SampleWindow(label: "周额度", valueText: "剩余 90%", progress: 0.90, colorHex: greenHex, resetText: "还剩 6 天 19 小时重置")
            ]
        ),
        SampleCard(
            name: "DeepSeek",
            badge: "API 余额",
            dotHex: 0x4D6BFE,
            windows: [
                SampleWindow(label: "账户可用余额（CNY）", valueText: "¥36.80", progress: 0.44, colorHex: amberHex, resetText: "充值 ¥35.00 · 赠送 ¥1.80")
            ]
        )
    ]

    var cursorY = popY + 80
    for card in cards {
        let cardH: CGFloat = card.windows.count == 2 ? 202 : 126
        let cardRect = CGRect(x: popX + 18, y: cursorY, width: popW - 36, height: cardH)

        ctx.saveGState()
        if !isDark {
            ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: rgba(0x0F172A, 0.05).cgColor)
        }
        fillRoundedRect(cardRect, radius: 18, color: cardBg)
        ctx.restoreGState()
        strokeRoundedRect(cardRect, radius: 18, color: cardBorder, width: 1)

        // 卡片标题行
        fillRoundedRect(CGRect(x: cardRect.minX + 18, y: cardRect.minY + 21, width: 11, height: 11), radius: 5.5, color: rgba(card.dotHex))
        drawText(card.name, at: CGPoint(x: cardRect.minX + 38, y: cardRect.minY + 14), font: NSFont.systemFont(ofSize: 18.5, weight: .semibold), color: textPrimary)

        let tagW: CGFloat = 88
        let tagRect = CGRect(x: cardRect.maxX - tagW - 18, y: cardRect.minY + 14, width: tagW, height: 24)
        fillRoundedRect(tagRect, radius: 12, color: pillBg)
        drawText(card.badge, at: CGPoint(x: tagRect.midX + 26, y: tagRect.minY + 3), font: NSFont.systemFont(ofSize: 13.5, weight: .medium), color: textMuted, rightAlign: true)

        var rowY = cardRect.minY + 54
        for w in card.windows {
            drawText(w.label, at: CGPoint(x: cardRect.minX + 18, y: rowY), font: NSFont.systemFont(ofSize: 16.5, weight: .regular), color: textSecondary)
            drawText(w.valueText, at: CGPoint(x: cardRect.maxX - 18, y: rowY), font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold), color: rgba(w.colorHex), rightAlign: true)

            let trackRect = CGRect(x: cardRect.minX + 18, y: rowY + 29, width: cardRect.width - 36, height: 9)
            fillRoundedRect(trackRect, radius: 4.5, color: trackBg)
            let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: max(12, trackRect.width * w.progress), height: 9)
            fillRoundedRect(fillRect, radius: 4.5, color: rgba(w.colorHex))

            drawText(w.resetText, at: CGPoint(x: cardRect.minX + 18, y: rowY + 45), font: NSFont.systemFont(ofSize: 14, weight: .regular), color: textMuted)
            rowY += 74
        }

        cursorY += cardH + 14
    }

    // 底部折叠条
    let drawerRect = CGRect(x: popX + 18, y: cursorY, width: popW - 36, height: 42)
    fillRoundedRect(drawerRect, radius: 14, color: cardBg)
    strokeRoundedRect(drawerRect, radius: 14, color: cardBorder, width: 1)
    drawText("▸  其他待接入平台（3）", at: CGPoint(x: drawerRect.minX + 16, y: drawerRect.minY + 11), font: NSFont.systemFont(ofSize: 14.5, weight: .medium), color: textMuted)
    drawText("展开", at: CGPoint(x: drawerRect.maxX - 16, y: drawerRect.minY + 11), font: NSFont.systemFont(ofSize: 14.5, weight: .medium), color: isDark ? rgba(0x60A5FA) : rgba(0x007AFF), rightAlign: true)

    // 底部分隔线与底栏
    let footerY = popRect.maxY - 52
    fillRoundedRect(CGRect(x: popX, y: footerY, width: popW, height: 1), radius: 0, color: dividerColor)

    let modePill = CGRect(x: popX + 18, y: footerY + 12, width: 98, height: 28)
    fillRoundedRect(modePill, radius: 8, color: pillBg)
    drawText("显示：剩余", at: CGPoint(x: modePill.minX + 12, y: modePill.minY + 5), font: NSFont.systemFont(ofSize: 14, weight: .medium), color: textSecondary)

    drawText("+ 导入平台  ·  退出", at: CGPoint(x: popRect.maxX - 18, y: footerY + 17), font: NSFont.systemFont(ofSize: 14.5, weight: .medium), color: textMuted, rightAlign: true)
}

drawPanelShowcase(originX: 28, isDark: false)
drawPanelShowcase(originX: 816, isDark: true)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Rendered UI showcase preview to \(outputPath)")
