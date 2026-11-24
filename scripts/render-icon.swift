import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: render-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

func cgColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: colorSpace, components: [r, g, b, alpha])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1. 浅色系温暖 macOS 圆角矩形画布（柔和浅粉白渐变，与声账家族无缝呼应）
let cardRect = CGRect(x: 64, y: 64, width: 896, height: 896)
let cardPath = roundedRect(cardRect, radius: 204)

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()

if let bgGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [cgColor(0xFFFDFB), cgColor(0xFBECE8), cgColor(0xF5DCD7)] as CFArray,
    locations: [0.0, 0.55, 1.0]
) {
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 120, y: 64), end: CGPoint(x: 900, y: 960), options: [])
}

// 顶部柔和暖光高光
if let topGlow = CGGradient(
    colorsSpace: colorSpace,
    colors: [cgColor(0xFFFFFF, alpha: 0.90), cgColor(0xFFFFFF, alpha: 0.0)] as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.drawRadialGradient(
        topGlow,
        startCenter: CGPoint(x: 512, y: 240),
        startRadius: 20,
        endCenter: CGPoint(x: 512, y: 240),
        endRadius: 480,
        options: []
    )
}
ctx.restoreGState()

// 浅色玻璃细腻外描边
ctx.addPath(roundedRect(CGRect(x: 68, y: 68, width: 888, height: 888), radius: 200))
ctx.setStrokeColor(cgColor(0xE4B5AE, alpha: 0.55))
ctx.setLineWidth(8)
ctx.strokePath()

// 2. 小猪主体（延续声账 & 小猪搭手的圆耳、奶白圆脸、珊瑚粉猪鼻与温和深棕炭描边）
ctx.saveGState()
ctx.translateBy(x: 0, y: -14)
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: cgColor(0x8C5852, alpha: 0.16))

let outlineColor = cgColor(0x2D2624)

// 左耳
let leftEar = CGMutablePath()
leftEar.move(to: CGPoint(x: 336, y: 292))
leftEar.addCurve(to: CGPoint(x: 320, y: 146), control1: CGPoint(x: 278, y: 234), control2: CGPoint(x: 272, y: 168))
leftEar.addCurve(to: CGPoint(x: 436, y: 234), control1: CGPoint(x: 368, y: 124), control2: CGPoint(x: 410, y: 168))
ctx.addPath(leftEar)
ctx.setFillColor(cgColor(0xF6C8C0))
ctx.fillPath()
ctx.addPath(leftEar)
ctx.setStrokeColor(outlineColor)
ctx.setLineWidth(28)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// 右耳
let rightEar = CGMutablePath()
rightEar.move(to: CGPoint(x: 688, y: 292))
rightEar.addCurve(to: CGPoint(x: 704, y: 146), control1: CGPoint(x: 746, y: 234), control2: CGPoint(x: 752, y: 168))
rightEar.addCurve(to: CGPoint(x: 588, y: 234), control1: CGPoint(x: 656, y: 124), control2: CGPoint(x: 614, y: 168))
ctx.addPath(rightEar)
ctx.setFillColor(cgColor(0xF6C8C0))
ctx.fillPath()
ctx.addPath(rightEar)
ctx.setStrokeColor(outlineColor)
ctx.setLineWidth(28)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// 奶白圆脸
let face = CGMutablePath()
face.move(to: CGPoint(x: 266, y: 470))
face.addCurve(to: CGPoint(x: 512, y: 228), control1: CGPoint(x: 266, y: 318), control2: CGPoint(x: 360, y: 228))
face.addCurve(to: CGPoint(x: 758, y: 470), control1: CGPoint(x: 664, y: 228), control2: CGPoint(x: 758, y: 318))
face.addCurve(to: CGPoint(x: 512, y: 686), control1: CGPoint(x: 758, y: 610), control2: CGPoint(x: 662, y: 686))
face.addCurve(to: CGPoint(x: 266, y: 470), control1: CGPoint(x: 362, y: 686), control2: CGPoint(x: 266, y: 610))
face.closeSubpath()

ctx.addPath(face)
ctx.setFillColor(cgColor(0xFFFFFF))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.addPath(face)
ctx.setStrokeColor(outlineColor)
ctx.setLineWidth(28)
ctx.setLineJoin(.round)
ctx.strokePath()

// 腮红
ctx.setFillColor(cgColor(0xE89A96, alpha: 0.48))
ctx.fillEllipse(in: CGRect(x: 328, y: 504, width: 68, height: 40))
ctx.fillEllipse(in: CGRect(x: 628, y: 504, width: 68, height: 40))

// 眼睛与高光
ctx.setFillColor(outlineColor)
ctx.fillEllipse(in: CGRect(x: 398, y: 414, width: 52, height: 52))
ctx.fillEllipse(in: CGRect(x: 574, y: 414, width: 52, height: 52))
ctx.setFillColor(cgColor(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: 410, y: 424, width: 15, height: 15))
ctx.fillEllipse(in: CGRect(x: 586, y: 424, width: 15, height: 15))

// 标志性珊瑚粉猪鼻
let snoutRect = CGRect(x: 414, y: 496, width: 196, height: 118)
let snoutPath = roundedRect(snoutRect, radius: 59)
ctx.saveGState()
ctx.addPath(snoutPath)
ctx.clip()
if let snoutGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [cgColor(0xFAD5CE), cgColor(0xE99E99)] as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.drawLinearGradient(snoutGrad, start: CGPoint(x: 512, y: 496), end: CGPoint(x: 512, y: 614), options: [])
}
ctx.restoreGState()

ctx.addPath(snoutPath)
ctx.setStrokeColor(outlineColor)
ctx.setLineWidth(24)
ctx.strokePath()

// 鼻孔
ctx.setFillColor(outlineColor)
ctx.fillEllipse(in: CGRect(x: 460, y: 536, width: 26, height: 38))
ctx.fillEllipse(in: CGRect(x: 538, y: 536, width: 26, height: 38))

ctx.restoreGState()

// 3. 底部浅色白玉胶囊进度条卡片（清爽苹果质感）
let panelRect = CGRect(x: 196, y: 676, width: 632, height: 196)
let panelPath = roundedRect(panelRect, radius: 48)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: cgColor(0x8C5852, alpha: 0.18))
ctx.addPath(panelPath)
ctx.setFillColor(cgColor(0xFFFFFF, alpha: 0.96))
ctx.fillPath()
ctx.restoreGState()

ctx.addPath(panelPath)
ctx.setStrokeColor(cgColor(0xEBD2CD, alpha: 0.90))
ctx.setLineWidth(7)
ctx.strokePath()

// 第一条：清爽翠绿 5 小时额度进度条
ctx.setFillColor(cgColor(0x22C55E))
ctx.fillEllipse(in: CGRect(x: 242, y: 726, width: 28, height: 28))

let track1 = roundedRect(CGRect(x: 292, y: 724, width: 482, height: 32), radius: 16)
ctx.addPath(track1)
ctx.setFillColor(cgColor(0xECEFF5))
ctx.fillPath()

let fill1 = roundedRect(CGRect(x: 292, y: 724, width: 368, height: 32), radius: 16)
ctx.saveGState()
ctx.addPath(fill1)
ctx.clip()
if let g1 = CGGradient(colorsSpace: colorSpace, colors: [cgColor(0x16A34A), cgColor(0x34D399)] as CFArray, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(g1, start: CGPoint(x: 292, y: 724), end: CGPoint(x: 660, y: 724), options: [])
}
ctx.restoreGState()

// 第二条：暖琥珀周额度进度条
ctx.setFillColor(cgColor(0xF59E0B))
ctx.fillEllipse(in: CGRect(x: 242, y: 794, width: 28, height: 28))

let track2 = roundedRect(CGRect(x: 292, y: 792, width: 482, height: 32), radius: 16)
ctx.addPath(track2)
ctx.setFillColor(cgColor(0xECEFF5))
ctx.fillPath()

let fill2 = roundedRect(CGRect(x: 292, y: 792, width: 248, height: 32), radius: 16)
ctx.saveGState()
ctx.addPath(fill2)
ctx.clip()
if let g2 = CGGradient(colorsSpace: colorSpace, colors: [cgColor(0xEA8C00), cgColor(0xFBBF24)] as CFArray, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(g2, start: CGPoint(x: 292, y: 792), end: CGPoint(x: 540, y: 792), options: [])
}
ctx.restoreGState()

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make CGImage\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Rendered light piggy icon to \(outputPath)")
